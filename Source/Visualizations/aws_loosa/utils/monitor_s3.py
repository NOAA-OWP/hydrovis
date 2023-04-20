import boto3
import os
import xarray as xr
import pandas as pd
from datetime import datetime, timedelta
import time
import re
import logging

from botocore.exceptions import ClientError
from aws_loosa.utils.shared_funcs import get_db_values

from aws_loosa.consts import consts
from aws_loosa.consts.paths import (PROCESSED_OUTPUT_BUCKET, PROCESSED_OUTPUT_PREFIX, TRIGGER_FILES_PREFIX,
                                        FIM_DATA_BUCKET)


def monitor_s3(forecast_date, max_flows_file, service_name, logger=None):
    """
        Tracks number of datasets in the FIM workspace for the process. Continues to compare number of processed HUCs
        with the number of expected HUCs. Once all HUCs are processed, datasets are moved to the published folder

        Args:
            forecast_date(datetime, str): Datetime of the forecast that is being processed
            max_flows_file(str): Streamflow file that is being used for the processing
            service_name(str): Name of the visualization process that is being ran
            logger(logging.logger): service specific Logger that should be used for logging
    """
    if not logger:
        logger = logging.getLogger()

    print("Configuring setup for S3 FIM monitoring")

    if isinstance(forecast_date, str):
        forecast_date = datetime.strptime(forecast_date, "%Y%m%dT%H%M%S")

    configuration, date, hour = get_configuration(max_flows_file)
    done_key = f"{TRIGGER_FILES_PREFIX}/{configuration}/trigger_files/{date}/{hour}_done.txt"

    logger.info("Subsetting data to get expected HUCs")
    dataset_type = 'rnr' if "replace_route" in max_flows_file else 'nwm'
    subset_df, all_HUCs = subset_streamflows(max_flows_file, dataset_type)

    s3_resource = boto3.resource('s3')
    s3 = boto3.client('s3')

    FIM_Bucket = s3_resource.Bucket(FIM_DATA_BUCKET)
    PROCESSED_BUCKET = s3_resource.Bucket(PROCESSED_OUTPUT_BUCKET)

    expected_hucs = get_hucs_to_process(dataset_type, all_HUCs, FIM_Bucket)
    logger.info(f"Expecting to process {len(expected_hucs)} HUCs")

    logger.info("Checking to see if timestep should be ran")
    timestep_processed = check_s3_file_existence(PROCESSED_OUTPUT_BUCKET, done_key)
    if timestep_processed:
        logger.info("FIM files have already been processed")
        return len(expected_hucs)

    logger.info(f"Checking FIM datasets in {PROCESSED_OUTPUT_PREFIX}/{configuration}/workspace/{date}/{hour}/mrf/")
    files_ready = False

    while not files_ready:

        processed_huc_keys = PROCESSED_BUCKET.objects.filter(
            Prefix=f'{PROCESSED_OUTPUT_PREFIX}/{configuration}/workspace/{date}/{hour}/mrf/'
        ).all()

        processed_huc_datasets = []
        for huc in processed_huc_keys:
            if huc.key.split(".")[-1] == 'mrf':
                if huc.key.split("/")[-1].split(".")[0] not in processed_huc_datasets:
                    processed_huc_datasets.append(huc.key.split("/")[-1].split(".")[0])

        missing_hucs = [huc for huc in expected_hucs if huc not in processed_huc_datasets]

        if not missing_hucs:
            files_ready = True
            break

        available = len(expected_hucs) - len(missing_hucs)
        logger.info(f"{available} out of {len(expected_hucs)} datasets are available")

        if available/len(expected_hucs) >= .8:
            logger.info(f"Missing the folowing HUCs: {missing_hucs}")

        print("Sleeping 1 minute to check if files are ready")
        time.sleep(60)

    # TODO: Create some type of strategy so that we arent overwriting the existing published data so early.
    move_data_to_published(configuration, date, hour)

    done_dir = os.path.join(os.getenv('TEMP'), service_name, date)
    if not os.path.exists(done_dir):
        os.makedirs(done_dir)

    tmp_done = os.path.join(os.getenv('TEMP'), service_name, date, f'{hour}_done.txt')
    f = open(tmp_done, "w")
    f.write("data is ready")
    f.close()

    logger.info(f"Output File count matches expected. Creating {done_key}.")
    s3.upload_file(tmp_done, PROCESSED_OUTPUT_BUCKET, done_key, ExtraArgs={'ServerSideEncryption': 'aws:kms'})

    return len(expected_hucs)


def check_s3_file_existence(bucket, file):
    """
        Checks S3 files to see if they exist

        Args:
            bucket(str): S3 bucket where the file resides
            file(str): key (path) to the file in the bucket

        Returns:
            Boolean: True if the file exists
    """
    s3_resource = boto3.resource('s3')
    try:
        s3_resource.Object(bucket, file).load()
        return True
    except ClientError as e:
        if e.response['Error']['Code'] == "404":
            return False
        else:
            raise


def get_configuration(filename):
    """
        Parses the data file path to extract the file configuration, date, hour, reference time, and input files.

        Args:
            filename(dictionary): key (path) of a NWM channel file, or max_flows derived file.

        Returns:
            configuration(str): configuration of the run, i.e. medium_range_3day, analysis_assim, etc
            date(str): date of the forecast file (YYYYMMDD)
            hour(str): hour of the forecast file (HH)
    """
    print("Parsing key to get configuration")
    if 'max_flows' in filename:
        matches = re.findall(r"max_flows-(.*)-(\d{8})\\.*_(\d{2})", filename)[0]
        date = matches[1]
        hour = matches[2]
        configuration = matches[0]

        days_match = re.findall(r"(\d+day)", filename)
        if days_match:
            configuration = f"{configuration}_{days_match[0]}"

    else:
        matches = re.findall(r"nwm.(\d{8})-(.*)\\nwm.t(\d{2})z", filename)[0]

        date = matches[0]
        configuration = matches[1]
        hour = matches[2]

        if 'medium_range' in configuration:
            configuration = 'medium_range'

    return configuration, date, hour


def move_data_to_published(configuration, date, hour):
    """
        Move FIM datasets from the FIM bucket workspace to the published folder in S3

        Args:
            configuration(str): Configuration of the process that is being ran, i.e. short_range, analysis_assim, etc
            date(str): date of the forecast file (YYYYMMDD)
            hour(str): hour of the forecast file (HH)
    """
    s3_resource = boto3.resource('s3')

    workspace_bucket = s3_resource.Bucket(PROCESSED_OUTPUT_BUCKET)
    workspace_prefix = f"{PROCESSED_OUTPUT_PREFIX}/{configuration}/workspace/{date}/{hour}/mrf/"
    published_bucket = s3_resource.Bucket(PROCESSED_OUTPUT_BUCKET)
    published_prefix = f"{PROCESSED_OUTPUT_PREFIX}/{configuration}/published/"

    print(f"Moving data from {workspace_prefix} to {published_prefix}")

    for obj in workspace_bucket.objects.filter(Prefix=workspace_prefix):
        old_source = {'Bucket': PROCESSED_OUTPUT_BUCKET,
                      'Key': obj.key}

        # replace the prefix
        new_key = obj.key.replace(workspace_prefix, published_prefix, 1)
        new_obj = published_bucket.Object(new_key)
        new_obj.copy(old_source, ExtraArgs={'ServerSideEncryption': 'aws:kms'})


def move_data_to_cache(configuration, date, hour):
    """
        Move FIM datasets from the FIM bucket workspace to the published folder in S3

        Args:
            configuration(str): Configuration of the process that is being ran, i.e. short_range, analysis_assim, etc
            date(str): date of the forecast file (YYYYMMDD)
            hour(str): hour of the forecast file (HH)
    """
    s3_resource = boto3.resource('s3')

    workspace_bucket = s3_resource.Bucket(PROCESSED_OUTPUT_BUCKET)
    workspace_prefix = f"{PROCESSED_OUTPUT_PREFIX}/{configuration}/workspace/{date}/{hour}/tif/"
    cache_bucket = s3_resource.Bucket(PROCESSED_OUTPUT_BUCKET)
    cache_prefix = f"{PROCESSED_OUTPUT_PREFIX}/{configuration}/cache/{date}/{hour}/"

    print(f"Moving data from {workspace_prefix} to {cache_prefix}")

    for obj in workspace_bucket.objects.filter(Prefix=workspace_prefix):
        old_source = {'Bucket': PROCESSED_OUTPUT_BUCKET,
                      'Key': obj.key}

        # replace the prefix
        new_key = obj.key.replace(workspace_prefix, cache_prefix, 1)
        new_obj = cache_bucket.Object(new_key)
        new_obj.copy(old_source, ExtraArgs={'ServerSideEncryption': 'aws:kms'})


def cleanup_cache(configuration, date, hour, buffer_days=14):
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

    cache_bucket = s3_resource.Bucket(PROCESSED_OUTPUT_BUCKET)

    # Determine the date threshold for keeping max flows files
    buffer_hours = int(buffer_days*24)
    forecast_date = datetime.strptime(f"{date}T{hour}", "%Y%m%dT%H")
    cache_date = forecast_date - timedelta(days=int(consts.CACHE_DAYS))

    # Loop through the buffer hours to try to delete old files, starting from the cache_date
    for hour in range(1, buffer_hours+1):
        buffer_date = cache_date - timedelta(hours=hour)
        buffer_time = buffer_date.strftime("%Y%m%d")
        buffer_hour = buffer_date.strftime("%H")

        cache_prefix = f"{PROCESSED_OUTPUT_PREFIX}/{configuration}/cache/{buffer_time}/{buffer_hour}/"
        cached_files = cache_bucket.objects.filter(Prefix=cache_prefix).all()

        print(f"Cleaning {cache_prefix}")
        for obj in cached_files:
            obj.delete()


def clean_workspace(configuration, date, hour):
    """
        Delete FIM datasets from the FIM bucket workspace after processing is completed

        Args:
            configuration(str): Configuration of the process that is being ran, i.e. short_range, analysis_assim, etc
            date(str): date of the forecast file (YYYYMMDD)
            hour(str): hour of the forecast file (HH)
    """
    s3_resource = boto3.resource('s3')

    workspace_bucket = s3_resource.Bucket(PROCESSED_OUTPUT_BUCKET)
    tif_workspace_prefix = f"{PROCESSED_OUTPUT_PREFIX}/{configuration}/workspace/{date}/{hour}/tif/"
    mrf_workspace_prefix = f"{PROCESSED_OUTPUT_PREFIX}/{configuration}/workspace/{date}/{hour}/mrf/"
    data_workspace_prefix = f"{PROCESSED_OUTPUT_PREFIX}/{configuration}/workspace/{date}/{hour}/data/"

    print(f"Cleaning {tif_workspace_prefix}")
    tif_files = workspace_bucket.objects.filter(Prefix=tif_workspace_prefix).all()
    for obj in tif_files:
        obj.delete()

    print(f"Cleaning {mrf_workspace_prefix}")
    mrf_files = workspace_bucket.objects.filter(Prefix=mrf_workspace_prefix).all()
    for obj in mrf_files:
        obj.delete()

    print(f"Cleaning {data_workspace_prefix}")
    data_files = workspace_bucket.objects.filter(Prefix=data_workspace_prefix).all()
    for obj in data_files:
        obj.delete()


def subset_streamflows(streamflow_file, dataset_type):
    """
        Subset features by high water thresholding. Also attach HUC value to features

        Args:
            streamflow_file(str): File that contains the forecast data
            dataset_type(str): The type of dataset that is being provided, i.e. nwm or rnr
    """
    # Open the max flows file and create a dataframe
    if ".nc" in streamflow_file:
        with xr.open_dataset(streamflow_file) as ds:
            df = ds[['feature_id', 'streamflow']].to_dataframe()
            df.reset_index(inplace=True)  # make sure feature_id is a column and not an index
    else:
        df = pd.read_csv(streamflow_file)
        df = df.rename(columns={'Feature ID': 'feature_id', 'Max Flow': 'streamflow'})

    df['streamflow'] = df['streamflow'].round(2)  # round streamflow values

    # Get the correct recurrence file based on domain
    if "_hi" in streamflow_file or "hawaii" in streamflow_file:
        recurrence_flows_table = "derived.recurrence_flows_hi"
    elif "_prvi" in streamflow_file or "puertorico" in streamflow_file:
        recurrence_flows_table = "derived.recurrence_flows_prvi"
    else:
        recurrence_flows_table = "derived.recurrence_flows_conus"

    # Get correct file and high flow threshold value for the domain
    df_high_water_threshold = get_db_values(recurrence_flows_table, ["feature_id", "high_water_threshold"])
    df_high_water_threshold = df_high_water_threshold.set_index('feature_id')

    df_hucs = get_db_values("derived.featureid_huc_crosswalk", ["feature_id", "huc6"])
    df_hucs = df_hucs.set_index('feature_id')

    df_meta = df_high_water_threshold.join(df_hucs)
    del df_high_water_threshold
    del df_hucs

    # Join recurrence flows and streamflow data
    df_joined = pd.merge(df, df_meta, on='feature_id', how='inner')
    del df_meta
    del df

    df_joined = df_joined.loc[df_joined['huc6'] > 0]
    df_joined['huc6'] = df_joined['huc6'].astype(int).astype(str).str.zfill(6)

    HUCs = df_joined['huc6'].unique()

    # Select features with streamflow above 0
    print("Subsetting streamflows")
    df_joined = df_joined[df_joined['streamflow'] > 0]

    print("Joined")

    if dataset_type == 'nwm':  # nwm fim (have to use this syntax way to avoid "ambiguous" error)
        df_joined = df_joined[df_joined["high_water_threshold"] > 0]  # Removed reaches with zero high flow threshold
        df_joined["high_water_threshold"] = df_joined["high_water_threshold"] / 35.3147  # cfs to cms conversion
        df_joined = df_joined[df_joined['streamflow'] >= df_joined["high_water_threshold"]]  # get subset of high flow threshold flows
    else:
        df_joined = df_joined[~df_joined['Viz Max Status'].isin(['no_flooding', 'none', 'no_forecast'])]
        df_joined = df_joined[df_joined['Waterbody Status'].isna()]
        df_joined = df_joined.set_index("feature_id")
        df_joined = df_joined[~df_joined.index.duplicated(keep="first")]
        df_joined = df_joined.reset_index()

    return df_joined, HUCs


def get_hucs_to_process(dataset_type, all_HUCs, FIM_Bucket):
    """
        Compare the HUCs from the streamflow file with the available FIM datasets on S3 to determine how many HUCs Will
        actually be processed

        Args:
            dataset_type(str): The type of dataset that is being provided, i.e. nwm or rnr
            all_HUCs(list): A list of all the HUCs from the forecast file
            FIM_Bucket(str): FIM bucket S3 connection
    """
    if dataset_type == "nwm":
        config = "fr"
    else:
        config = "ms"

    # Connect to the FIM bucket and query all specified datasets to get HUCs with available data.
    huc_keys = FIM_Bucket.objects.filter(Prefix=f'fim_{os.environ["FIM_VERSION"].replace(".", "_")}_{config}_c/').all()

    # Loop through queried HUCs and keep track of which exist
    available_huc_datasets = []
    for huc_key in huc_keys:
        try:
            huc = re.findall(r"/(\d{6})/", huc_key.key)[0]
            if huc not in available_huc_datasets:
                available_huc_datasets.append(huc)
        except Exception:
            continue

    # TODO: Do we need to be doing this? I wouldnt think so
    if dataset_type == "rnr":
        return available_huc_datasets

    # Extract all HUCs that exist within the streamflow file and also have S3 FIM datasets
    hucs_to_process = [huc for huc in all_HUCs if huc in available_huc_datasets]

    if not hucs_to_process:
        raise Exception("No HUCs are expected. Check code and paths.")

    return hucs_to_process
