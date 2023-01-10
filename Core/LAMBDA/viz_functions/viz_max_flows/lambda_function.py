import json
import os
from datetime import datetime, timedelta
import xarray
import pandas as pd
import numpy as np
import boto3
import botocore
import urllib.parse
import time

from viz_lambda_shared_funcs import get_configuration, check_s3_file_existence
from es_logging import get_elasticsearch_logger
es_logger = get_elasticsearch_logger()

MAX_FLOWS_BUCKET = os.environ['MAX_FLOWS_BUCKET']
CACHE_DAYS = os.environ['CACHE_DAYS']
INITIALIZE_PIPELINE_FUNCTION = os.environ['INITIALIZE_PIPELINE_FUNCTION']


def lambda_handler(event, context):
    """
        The lambda handler is the function that is kicked off with the lambda. This function will take all the
        forecast steps in the NWM configuration, calculate the max streamflow for each feature and then save the
        output in S3

        Args:
            event(event object): An event is a JSON-formatted document that contains data for a Lambda function to
                                 process
            context(object): Provides methods and properties that provide information about the invocation, function,
                             and runtime environment
    """
    # parse the event to get the bucket and file that kicked off the lambda
    print("Parsing key to get configuration")
    if "Records" in event:
        message = json.loads(event["Records"][0]['Sns']['Message'])
        data_key = urllib.parse.unquote_plus(message["Records"][0]['s3']['object']['key'], encoding='utf-8')
        data_bucket = message["Records"][0]['s3']['bucket']['name']
    else:
        data_key = event['data_key']
        data_bucket = event['data_bucket']

    if not check_s3_file_existence(data_bucket, data_key):
        raise Exception(f"{data_key} does not exist within {data_bucket}")

    max_flow_calcs = []  # Store max flows in list just in case multiplens needed
    metadata = get_configuration(data_key, mrf_timestep=3)
    configuration = metadata.get('configuration')
    date = metadata.get('date')
    hour = metadata.get('hour')
    forecast_timestep = metadata.get('forecast_timestep')

    # Setup an input files dictionary with the bucket
    input_files = metadata.get('input_files')
    files = []
    s3_file_sets = []
    for s3_key in input_files:
        files.append({'bucket': data_bucket, 's3_key': s3_key})
    s3_file_sets.append(files)

    if "medium_range" in configuration:
        configuration = "medium_range"

    short_hand_config = configuration.replace("analysis_assim", "ana").replace("short_range", "srf").replace("medium_range", "mrf")  # noqa
    short_hand_config = short_hand_config.replace("hawaii", "hi").replace("puertorico", "prvi")
    subset_config = None

    if configuration == 'medium_range':
        subset_config = f"{int(int(forecast_timestep)/24)}day"
        short_hand_config = f"{short_hand_config}_{subset_config}"

    max_flow_calcs.append(short_hand_config)  # Add the current configuration to calcs list.

    if configuration == 'analysis_assim':
        # Only perform max flows computation for analysis_assim when its the 00Z timestep
        if hour != "00":
            print(f"{data_key} is not a file for 00Z so max flows will not be calculated")
            return
        else:
            max_flow_calcs = []  # If running ana, reset the calcs list and s3_file_sets list
            s3_file_sets = []
            days = [7, 14]
            for day in days:
                files = []
                previous_forecasts = day*24
                metadata = get_configuration(data_key, previous_forecasts=previous_forecasts)
                input_files = metadata.get('input_files')
                print(len(input_files))
                for s3_key in input_files:
                    files.append({'bucket': data_bucket, 's3_key': s3_key})
                s3_file_sets.append(files)
                reference_time = metadata.get('reference_time')
                subset_config = f"{int(previous_forecasts/24)}day"
                short_hand_config = f"ana_{subset_config}"
                max_flow_calcs.append(short_hand_config)

    es_logger.info(f"Creating max flows file for {configuration} for {date}T{hour}:00:00Z")

    for n, max_flow_calc in enumerate(max_flow_calcs):
        output_netcdf = f"max_flows/{configuration}/{date}/{max_flow_calc}_{hour}_max_flows.nc"

        # Once the files exist, calculate the max flows
        calculate_max_flows(s3_file_sets[n], output_netcdf)
        es_logger.info(f"Successfully created max flows file for {configuration} for {date}T{hour}:00:00Z")

        # If analysis_assim, trigger the db ingest function
        if max_flow_calc=='ana_14day':
            trigger_db_ingest(configuration, 14, reference_time, MAX_FLOWS_BUCKET, output_netcdf)

        # If max calcs will run more than once, remove duplicates and
        # update the second set of input files to include the just created max file.
        next = n+1
        if len(s3_file_sets) > (next):
            s3_file_sets[next] = [file_next for file_next in s3_file_sets[next] if file_next not in s3_file_sets[n]]
            s3_file_sets[next].append({'bucket': MAX_FLOWS_BUCKET, 's3_key': output_netcdf})

    # Cleanup old max flows files beyond the cache
    cleanup_cache(configuration, date, max_flow_calcs[-1], hour)

    print("Done")


def calculate_max_flows(s3_files, output_netcdf):
    """
        Iterates through a times series of National Water Model (NWM) channel_rt output NetCDF files, and finds the
        maximum flow of each NWM reach during this period.  Outputs a NetCDF file containing all NWM reaches and their
        maximum flows.

        Args:
            data_bucket (str): S3 bucket name where the NWM files are stored
            path_to_nwm_files (str or list): Path to the directory or list of the paths to the files to caclulate
                                             maximum flows on.
            output_netcdf (str): Key (path) of the max flows netcdf that will be store in S3
    """
    print("--> Calculating flows")
    peak_flows, feature_ids = calc_max_flows(s3_files)  # creates a max flow array for all reaches

    print(f"--> Creating {output_netcdf}")
    write_netcdf(feature_ids, peak_flows, output_netcdf)  # creates the output NetCDF file


def download_file(data_bucket, file_path, download_path):
    s3 = boto3.client('s3')

    try:
        s3.download_file(data_bucket, file_path, download_path)
        return True
    except Exception as e:
        print(f"File failed to download {file_path}: {e}")
        return False


def calc_max_flows(s3_files):
    """
        Iterates through a times series of National Water Model (NWM) channel_rt output NetCDF files, and finds
        the maximum flow of each NWM reach during this period.

        Args:
            data_bucket (str): S3 bucket name where the NWM files are stored
            active_file_paths (str or list): Path to the directory or list of the paths to the files to caclulate
                                             maximum flows on.

        Returns:
            max_flows (numpy array): Numpy array that contains all the max flows for each feature for the forecast
            feature_ids (numpy array): Numpy array that contains all the features ids for the forecast
    """
    max_flows = None
    feature_ids = None
    tries = 0

    # Loop through the NWM files and keep track of the max flows each time
    while tries < 12:
        unavailable_files = []

        for file in s3_files:
            data_bucket = file['bucket']
            file_path = file['s3_key']
            if not check_s3_file_existence(data_bucket, file_path):
                unavailable_files.append(file_path)

        tries += 1

        if unavailable_files and tries < 12:
            es_logger.info(f"Missing the following files: {unavailable_files}. Trying again in 1 minute")
            time.sleep(60)
        elif unavailable_files:
            error_message = f"Missing the following files: {unavailable_files}. Retries maxed"
            es_logger.error(error_message)
            raise Exception(error_message)
        else:
            es_logger.info("All files exist in S3 bucket")
            break

    for file in s3_files:
        data_bucket = file['bucket']
        file_path = file['s3_key']
        download_path = f'/tmp/{os.path.basename(file_path)}'
        print(f"--> Downloading {file_path} to {download_path}")
        download_file(data_bucket, file_path, download_path)

        with xarray.open_dataset(download_path) as ds:
            temp_flows = ds['streamflow'].values  # imports the streamflow values from each file
            if max_flows is None:
                max_flows = temp_flows
            if feature_ids is None:
                feature_ids = ds['feature_id'].values

        print(f"--> Removing {download_path}")
        os.remove(download_path)

        # compares the streamflow values in each file with those stored in the max_flows array, and keeps the
        # maximum value for each reach
        max_flows = np.maximum(max_flows, temp_flows)

    return max_flows, feature_ids


def write_netcdf(feature_ids, peak_flows, output_netcdf):
    """
        Iterates through a times series of National Water Model (NWM) channel_rt output NetCDF files, and finds the
        maximum flow of each NWM reach during this period.

        Args:
            feature_ids (numpy array): Numpy array that contains all the features ids for the forecast
            peak_flows (numpy array): Numpy array that contains all the max flows for each feature for the forecast
            output_netcdf (str or list): Key (path) of the max flows netcdf that will be store in S3
    """
    s3 = boto3.client('s3')

    tmp_netcdf = '/tmp/max_flows.nc'

    # Create a dataframe from the feature ids and streamflow
    df = pd.DataFrame(feature_ids, columns=['feature_id']).set_index('feature_id')
    df['streamflow'] = peak_flows
    df['streamflow'] = df['streamflow'].fillna(0)

    # Save the max flows dataframe to a loacl netcdf file
    df.to_xarray().to_netcdf(tmp_netcdf)

    # Upload the local max flows file to the S3 bucket
    s3.upload_file(tmp_netcdf, MAX_FLOWS_BUCKET, output_netcdf, ExtraArgs={'ServerSideEncryption': 'aws:kms'})
    os.remove(tmp_netcdf)


def cleanup_cache(configuration, date, short_hand_config, hour, buffer_days=30):
    """
        Cleans up old max flows files that are beyond the cache

        Args:
            configuration(str): The configuration for the forecast being processed
            date(str): The date for the forecast being processed
            short_hand_config(str): The short-hand NWM configuration for the forecast being processed
            hour(str): The hour for the forecast being processed
            buffer_days(int): The number of days of max flows files to keep
    """
    s3_resource = boto3.resource('s3')

    # Determine the date threshold for keeping max flows files
    buffer_hours = int(buffer_days*24)
    forecast_date = datetime.strptime(f"{date}T{hour}", "%Y%m%dT%H")
    cache_date = forecast_date - timedelta(days=int(CACHE_DAYS))

    # Loop through the buffer hours to try to delete old files, starting from the cache_date
    for hour in range(1, buffer_hours+1):
        buffer_date = cache_date - timedelta(hours=hour)
        buffer_time = buffer_date.strftime("%Y%m%d")
        buffer_hour = buffer_date.strftime("%H")

        buffer_file = f"max_flows/{configuration}/{buffer_time}/{short_hand_config}_{buffer_hour}_max_flows.nc"

        if check_s3_file_existence(MAX_FLOWS_BUCKET, buffer_file):
            s3_resource.Object(MAX_FLOWS_BUCKET, buffer_file).delete()
            print(f"Deleted file {buffer_file} from {MAX_FLOWS_BUCKET}")


def trigger_db_ingest(configuration, days, reference_time, bucket, s3_file_path):
    """
        Triggers the db_ingest lambda function to ingest a specific file into the vizprocessing db.

        Args:
            configuration(str): The configuration for the forecast being processed
            reference_time (datetime): The reference time of the originating forecast
            bucket (str): The s3 bucket containing the file.
            s3_file_path (str): The s3 path to ingest into the db.
    """
    lambda_config = botocore.client.Config(max_pool_connections=1, connect_timeout=60, read_timeout=600)
    lambda_client = boto3.client('lambda', config=lambda_config)

    dump_dict = {"data_key": s3_file_path, "configuration": f"{configuration}_{days}day",
                 "data_bucket": bucket, "invocation_type": "event"}
    lambda_client.invoke(FunctionName=INITIALIZE_PIPELINE_FUNCTION, InvocationType='Event', Payload=json.dumps(dump_dict))
    print(f"Invoked db_ingest function with payload: {dump_dict}.")
