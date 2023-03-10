import json
import os
import datetime
import xarray
import pandas as pd
import numpy as np
import boto3
import botocore
import urllib.parse
import time
import re
import collections
import isodate
import requests

from viz_classes import s3_file, database

MAX_FLOWS_BUCKET = os.environ['MAX_FLOWS_BUCKET']
CACHE_DAYS = os.environ['CACHE_DAYS']
INITIALIZE_PIPELINE_FUNCTION = os.environ['INITIALIZE_PIPELINE_FUNCTION']

class MissingS3FileException(Exception):
    """ my custom exception class """

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
    ###### Initialize the pipeline class & configuration classes ######
    #Initialize the pipeline object - This will parse the lambda event, initialize a configuration, and pull service metadata for that configuration from the viz processing database.
    try:
        pipeline = viz_lambda_pipeline(event, max_flow_method="lambda") # This does a ton of stuff - see the viz_pipeline class below for details.
        invoke_step_function = pipeline.start_event.get('invoke_step_function') if 'invoke_step_function' in pipeline.start_event else True
    except Exception as e:
        print("Error: Pipeline failed to initialize.")
        raise e
        
    if 'analysis_assim' in pipeline.configuration.name:
        # Only perform max flows computation for analysis_assim when its the 00Z timestep
        if pipeline.configuration.reference_time.hour != 0:
            print(f"{pipeline.configuration.reference_time} is not for 00Z so max flows will not be calculated")
            return

    config = pipeline.configuration.name
    short_hand_config = config.replace("analysis_assim", "ana").replace("short_range", "srf").replace("medium_range", "mrf")  # noqa
    short_hand_config = short_hand_config.replace("hawaii", "hi").replace("puertorico", "prvi")
    subset_config = None

    file_datasets = {}
    for service_name, flow_id_data in pipeline.configuration.service_input_files.items():
        for flow_id, s3_keys in flow_id_data.items():
            service_metadata = [service for service in pipeline.configuration.db_data_flow_metadata if service['service'] == service_name and service['flow_id'] == flow_id][0]
            if service_metadata['step'] != "max_flows":
                continue
            
            file_dataset = []
            for s3_key in s3_keys:
                file = check_if_file_exists(pipeline.configuration.input_bucket, s3_key)
                file_dataset.append({"s3_key": file, "s3_bucket": pipeline.configuration.input_bucket})
            
            first_file_pipeline = viz_lambda_pipeline({"data_key": file_dataset[0]['s3_key'], "data_bucket": pipeline.configuration.input_bucket})
            first_file_reference_time = first_file_pipeline.configuration.reference_time
            
            last_file_pipeline = viz_lambda_pipeline({"data_key": file_dataset[-1]['s3_key'], "data_bucket": pipeline.configuration.input_bucket})
            last_file_reference_time = last_file_pipeline.configuration.reference_time
            
            delta = (last_file_reference_time - first_file_reference_time).total_seconds()

            if (delta/(60*60*24)).is_integer():
                delta = f"_{int(delta/(60*60*24))}day"
            else:
                delta = f"_{int(delta/(60*60))}hour"
            
            if "day" in short_hand_config:
                short_hand_config = re.sub("_[0-9]*day", delta, short_hand_config)
            elif "hour" in short_hand_config:
                short_hand_config = re.sub("_[0-9]*hour", delta, short_hand_config)
            else:
                short_hand_config = f"{short_hand_config}{delta}"
                
            file_datasets[short_hand_config] = {"files": file_dataset, "config": service_metadata['target_table']}
    
    file_datasets = dict(sorted(file_datasets.items(), key=lambda i: len(i[1]['files'])))
    keys = list(file_datasets.keys())
    reference_time = pipeline.configuration.reference_time
    date = reference_time.strftime("%Y%m%d")
    hour = reference_time.strftime("%H")
        
    for n, file_dataset_key in enumerate(keys):
        short_hand_config = keys[n]
        file_dataset = file_datasets[short_hand_config]['files']
        config = file_datasets[short_hand_config]['config']
        print(f"Creating max flows file for {short_hand_config} for {date}T{hour}:00:00Z")
        output_netcdf = f"max_flows/{config}/{date}/{short_hand_config}_{hour}_max_flows.nc"

        # Once the files exist, calculate the max flows
        calculate_max_flows(file_dataset, output_netcdf)
        print(f"Successfully created max flows file for {output_netcdf}")

        # If analysis_assim, trigger the db ingest function
        if 'ana_14day' in short_hand_config or 'ana_para_14day' in short_hand_config:
            trigger_db_ingest(config, pipeline.configuration.reference_time, MAX_FLOWS_BUCKET, output_netcdf)

        # If max calcs will run more than once, remove duplicates and
        # update the second set of input files to include the just created max file.
        next = n+1
        if len(file_datasets) > (next):
            file_datasets[keys[next]]['files'] = [file_next for file_next in file_datasets[keys[next]]['files'] if file_next not in file_datasets[short_hand_config]['files']]
            file_datasets[keys[next]]['files'].append({"s3_key": output_netcdf, "s3_bucket": MAX_FLOWS_BUCKET})

        #Cleanup old max flows files beyond the cache
        cleanup_cache(config, reference_time, short_hand_config)

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
    peak_flows, feature_ids, nwm_vers = calc_max_flows(s3_files)  # creates a max flow array for all reaches

    print(f"--> Creating {output_netcdf}")
    write_netcdf(feature_ids, peak_flows, nwm_vers, output_netcdf)  # creates the output NetCDF file


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
    nwm_vers = None

    for file_dataset in s3_files:
        file_path = file_dataset['s3_key']
        data_bucket = file_dataset['s3_bucket']
        download_path = f'/tmp/{os.path.basename(file_path)}'
        print(f"--> Downloading {file_path} to {download_path}")
        download_file(data_bucket, file_path, download_path)

        with xarray.open_dataset(download_path) as ds:
            temp_flows = ds['streamflow'].values  # imports the streamflow values from each file
            if not nwm_vers:
                print(download_path)
                nwm_vers = float(ds.NWM_version_number.replace("v",""))
            if max_flows is None:
                max_flows = temp_flows
            if feature_ids is None:
                feature_ids = ds['feature_id'].values

        print(f"--> Removing {download_path}")
        os.remove(download_path)

        # compares the streamflow values in each file with those stored in the max_flows array, and keeps the
        # maximum value for each reach
        max_flows = np.maximum(max_flows, temp_flows)

    return max_flows, feature_ids, nwm_vers


def write_netcdf(feature_ids, peak_flows, nwm_vers, output_netcdf):
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
    df['nwm_vers'] = nwm_vers

    # Save the max flows dataframe to a loacl netcdf file
    df.to_xarray().to_netcdf(tmp_netcdf)

    # Upload the local max flows file to the S3 bucket
    s3.upload_file(tmp_netcdf, MAX_FLOWS_BUCKET, output_netcdf, ExtraArgs={'ServerSideEncryption': 'aws:kms'})
    os.remove(tmp_netcdf)


def cleanup_cache(configuration, forecast_date, short_hand_config, buffer_days=30):
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
    cache_date = forecast_date - datetime.timedelta(days=int(CACHE_DAYS))

    # Loop through the buffer hours to try to delete old files, starting from the cache_date
    for hour in range(1, buffer_hours+1):
        buffer_date = cache_date - datetime.timedelta(hours=hour)
        buffer_time = buffer_date.strftime("%Y%m%d")
        buffer_hour = buffer_date.strftime("%H")

        buffer_file = f"max_flows/{configuration}/{buffer_time}/{short_hand_config}_{buffer_hour}_max_flows.nc"

        try:
            check_if_file_exists(MAX_FLOWS_BUCKET, buffer_file)
            s3_resource.Object(MAX_FLOWS_BUCKET, buffer_file).delete()
            print(f"Deleted file {buffer_file} from {MAX_FLOWS_BUCKET}")
        except MissingS3FileException:
            pass


def trigger_db_ingest(configuration, reference_time, bucket, s3_file_path):
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

    dump_dict = {"data_key": s3_file_path, "configuration": configuration,
                 "data_bucket": bucket, "invocation_type": "event"}
    lambda_client.invoke(FunctionName=INITIALIZE_PIPELINE_FUNCTION, InvocationType='Event', Payload=json.dumps(dump_dict))
    print(f"Invoked db_ingest function with payload: {dump_dict}.")
    
def check_if_file_exists(bucket, file):
    if "https" in file:
        if requests.head(file).status_code == 200:
            print(f"{file} exists.")
            return file
        else:
            raise Exception(f"https file doesn't seem to exist: {file}")
        
    else:
        if s3_file(bucket, file).check_existence():
            print("File exists on S3.")
            return file
        elif "/prod" in file:
            google_file = file.replace('common/data/model/com/nwm/prod', 'https://storage.googleapis.com/national-water-model')
            if requests.head(google_file).status_code == 200:
                print("File does not exist on S3 (even though it should), but does exists on Google Cloud.")
                return google_file
        elif "/para" in file:
            para_nomads_file = file.replace("common/data/model/com/nwm/para", "https://para.nomads.ncep.noaa.gov/pub/data/nccf/com/nwm/para")
            if requests.head(para_nomads_file).status_code == 200:
                print("File does not exist on S3 (even though it should), but does exists on NOMADS para.")
                
                download_path = f'/tmp/{os.path.basename(para_nomads_file)}'
                open(download_path, 'wb').write(requests.get(para_nomads_file, allow_redirects=True).content)
                
                print(f"Saving {file} to {bucket} for archiving")
                s3 = boto3.client('s3')
                s3.upload_file(download_path, bucket, file)
                os.remove(download_path)
                return file

        raise MissingS3FileException(f"{file} does not exist on S3.")
    
###################################################################################################################################################
################################################################### Viz Classes ###################################################################
###################################################################################################################################################
# Two foundational pipeline classes are defined below, which make-up any given viz pipeline. The general heirarchy is as such:
# -> viz_pipeline
# ---> configuration
# ------> service (not currently a class - may make sense to define as such in the future)
###################################################################################################################################################

###################################################################################################################################################
## Viz Pipeline Class
###################################################################################################################################################
# This class contains all the attributes for a given pipeline. It is designed to be used in the viz_initialize_pipeline lambda function... but
# should be transplantable elsewhere if/when needed.

class viz_lambda_pipeline:
    
    def __init__(self, start_event, print_init=True, max_flow_method="pipeline"):
        # At present, we're always initializing from a lambda event
        self.start_event = start_event
        if self.start_event.get("detail-type") == "Scheduled Event":
            self.invocation_type = "eventbridge" 
        elif "Records" in self.start_event: # Records in the start_event denotes a SNS trigger of the lambda function.
            self.invocation_type = "sns" 
        elif "invocation_type" in self.start_event: # Currently the max_flows and wrds_api_handler lambda functions manually invoke this lambda function and specify a "invocation_type" key in the payload. This is how we identify that.
            self.invocation_type = "lambda" #TODO: Clean this up to actually pull the value from the payload
        else: 
            self.invocation_type = "manual"
        self.job_type = "auto" if not self.start_event.get('reference_time') else "past_event" # We assume that the specification of a reference_time in the payload correlates to a past_event run.
        self.keep_raw = True if self.job_type == "past_event" and self.start_event.get('keep_raw') else False # Keep_raw will determine if a past_event run preserves the raw ingest data tables in the archive schema, or recycles them.
        self.start_time = datetime.datetime.fromtimestamp(time.time())

        if self.start_event.get("detail-type") == "Scheduled Event":
            config, self.reference_time, bucket = s3_file.from_eventbridge(self.start_event)
            self.configuration = configuration(config, reference_time=self.reference_time, input_bucket=bucket, max_flow_method=max_flow_method)
        # Here is the logic that parses various invocation types / events to determine the configuration and reference time.
        # First we see if a S3 file path is what initialized the function, and use that to determine the appropriate configuration and reference_time.
        elif self.invocation_type == "sns" or self.start_event.get('data_key'):
            self.start_file = s3_file.from_lambda_event(self.start_event)
            configuration_name, self.reference_time, bucket = configuration.from_s3_file(self.start_file)
            self.configuration = configuration(configuration_name, reference_time=self.reference_time, input_bucket=bucket, max_flow_method=max_flow_method)
        # If a manual invokation_type, we first look to see if a reference_time was specified and use that to determine the configuration.
        elif self.invocation_type == "manual":
            if self.start_event.get('reference_time'):
                self.reference_time = datetime.datetime.strptime(self.start_event.get('reference_time'), '%Y-%m-%d %H:%M:%S')
                self.configuration = configuration(start_event.get('configuration'), reference_time=self.reference_time, input_bucket=start_event.get('bucket'), max_flow_method=max_flow_method)
            # If no reference time was specified, we get the most recent file available on S3 for the specified configruation, and use that.
            else:
                most_recent_file = s3_file.get_most_recent_from_configuration(configuration_name=start_event.get('configuration'), bucket=start_event.get('bucket'))
                self.start_file = most_recent_file
                configuration_name, self.reference_time, bucket = configuration.from_s3_file(self.start_file)
                self.configuration = configuration(configuration_name, reference_time=self.reference_time, input_bucket=bucket, max_flow_method=max_flow_method)
        
        # Get some other useful attributes for the pipeline, given the attributes we now have.
        self.most_recent_ref_time, self.most_recent_start = self.get_last_run_info()
        self.pipeline_services = self.configuration.services_to_run
        self.pipeline_max_flows =  self.configuration.max_flows # Max_Flows will post-process BEFORE service post-processing
        
        self.sql_rename_dict = {} # Empty dictionary for use in past events, if table renames are required. This dictionary is utilized through the pipline as key:value find:replace on SQL files to use tables in the archive schema.
        self.organize_db_import() #This method organizes input table metadata based on the admin.pipeline_data_flows db table, and updates the sql_rename_dict dictionary if/when needed for past events.
        
        # Print a nice tidy summary of the initialized pipeline for logging.
        if print_init:
            self.__print__() 
    
    ###################################
    # This method gathers information on the last pipeline run for the given configuration
    # TODO: This should totally be in the configuration class... and we should abstract a view to access this information.
    def get_last_run_info(self):
        viz_db = database(db_type="viz")
        with viz_db.get_db_connection() as connection:
            cur = connection.cursor()
            cur.execute(f"""
                        SELECT max(reference_time) as reference_time, last_update
                        FROM (SELECT max(update_time) as last_update from admin.ingest_status a
                                JOIN admin.pipeline_data_flows b ON a.target = b.target_table
                                JOIN admin.services c on b.service = c.service
                                WHERE configuration = '{self.configuration.name}' and status = 'Import Started' AND step = 'ingest') as last_start
                        JOIN admin.ingest_status a ON last_start.last_update = a.update_time
                        JOIN admin.pipeline_data_flows b on a.target = b.target_table
                        JOIN admin.services c ON b.service = c.service
                        WHERE c.configuration = '{self.configuration.name}' AND b.step = 'ingest'
                        GROUP BY last_update
                        """)
            try:
                return cur.fetchone()[0], cur.fetchone()[1]
            except: #if nothing logged in db, return generic datetimes in the past
                return datetime.datetime(2000, 1, 1, 0, 0, 0), datetime.datetime(2000, 1, 1, 0, 0, 0)
    
    ###################################
    # This method organizes input table metadata based on the admin.pipeline_data_flows db table, and updates the sql_rename_dict to relevant pipeline_info dictionary items.
    # It produces one new pipeline class attribute: ingest_files, which is the list of S3 file paths and their respective db destination tables.
    # TODO: Find someway to use an actual map to figure this all out - sooooo much looping and redundant assignments happening here. This is very messy
    def organize_db_import(self, run_only=True): 
        self.ingest_files = []
        db_prefix = ""
        self.db_data_flow_metadata = self.configuration.db_data_flow_metadata # copy the configuration db import metadata to a pipeline attribute
        
        ##### If running a past event #####
        if self.job_type == "past_event":
            ref_prefix = f"ref_{self.configuration.reference_time.strftime('%Y%m%d_%H%M_')}" # replace invalid characters as underscores in ref time.
            if self.keep_raw:  # If storing raw data is desirable, add a ref_time prefix
                db_prefix = ref_prefix
            else:
                db_prefix = ref_prefix #"temp_" - Using ref_prefix for now until I can think this through a little more. Need a way to remove these raw files for non keep_raw jobs.
            
            # Update target tables to use the archive schema with dynamic table names, and start a rename dictionary to pass through to the postprocess_sql function to use the correct tables.
            for db_flow in self.db_data_flow_metadata:
                db_flow['original_table'] = db_flow['target_table']
                db_flow['target_table'] = 'archive' + '.' + db_prefix + 'raw_' + db_flow['target_table'].split('.')[1]
                self.sql_rename_dict.update({db_flow['original_table']: db_flow['target_table']})
            # Add new service tables as well
            for service in self.pipeline_services:
                self.sql_rename_dict.update({'publish.' + service['service']: 'archive' + '.' + ref_prefix + service['service']})
            # Add new summary tables as well
            for service in [service for service in self.pipeline_services if service['postprocess_summary'] is not None]:
                for postprocess_summary in service['postprocess_summary']:
                    self.sql_rename_dict.update({'publish.' + postprocess_summary: 'archive' + '.' + ref_prefix + postprocess_summary})
        
        ########
        # Now, let's loop through all the input files in the configuration and assign db destination tables and keys now that we've completed the above logic.
        added_files = {}
        for service_name, flow_id_data in self.configuration.service_input_files.items():
            for flow_id, s3_keys in flow_id_data.items():
                service_metadata = [service for service in self.db_data_flow_metadata if service['service'] == service_name and service['flow_id'] == flow_id][0]
                
                original_table = service_metadata['original_table'] if self.job_type == "past_event" else service_metadata['target_table']
                ingest_table = service_metadata['target_table']
                ingest_keys = service_metadata['target_keys']

                if original_table not in added_files and ingest_table not in added_files:
                    added_files[ingest_table] = []

                for s3_key in s3_keys:
                    if s3_key in added_files[ingest_table]:
                        continue

                    self.ingest_files.append({'s3_key': s3_key, 'original_table': original_table, 'ingest_table': ingest_table, 'ingest_keys': ingest_keys}) # Add each file to the new pipeline ingest_files list.
                    added_files[ingest_table].append(s3_key)
                
        if self.configuration.data_type != "channel":
            for service in self.pipeline_services:
                service_name = service['service']
                service['input_files'] = sorted({x for v in self.configuration.service_input_files[service_name].values() for x in v})
                service['bucket'] = self.configuration.input_bucket
    
    ###################################
    def __print__(self):
        print(f"""
        Viz Pipeline Run:
          Configuration: {self.configuration.name}
          Reference Time: {self.configuration.reference_time}
          Invocation Type: {self.invocation_type}
          Job Type: {self.job_type}
          Keep Raw Files: {self.keep_raw}
          Start Time: {self.start_time.strftime('%Y-%m-%d %H:%M:%S')}
        """)

###################################################################################################################################################
## Configuration Class
###################################################################################################################################################
# This class is essentially a sub-class of viz_pipeline that denotes a common unit/aggregation of data source.
# A configuration defines the data sources that a set of services require to run, and is primarily used to define the ingest files that must be
# compiled before various service data can be generated. A particular reference_time is always associted with a configuration.
# Example Configurations:
#   - short_range - A NWM short_range forecast... used for services like srf_max_high_flow_magnitude, srf_high_water_arrival_time, srf_max_inundation, etc.
#   - medium_range_mem1 - The first ensemble member of a NWM medium_range forecast... used for services like mrf_max_high_flow_magnitude, mrf_high_water_arrival_time, mrf_max_inundation, etc.
#   - ahps - The ahps RFC forecast and location data (currently gathered from the WRDS forecast and location APIs) that are required to produce rfc_max_stage service data.
#   - replace_route - The ourput of the replace and route model that are required to produce the rfc_5day_max_downstream streamflow and inundation services.

class configuration:
    def __init__(self, name, reference_time=None, input_bucket=None, input_files=None, max_flow_method="pipeline"): #TODO: Futher build out ref time range.
        self.name = name
        self.reference_time = reference_time
        self.input_bucket = input_bucket
        self.service_metadata = self.get_service_metadata(max_flow_method=max_flow_method)
        self.db_data_flow_metadata = self.get_db_data_flow_metadata(max_flow_method=max_flow_method)
        self.services_to_run = [service for service in self.service_metadata if service['run']] #Pull the relevant configuration services into a list.
        self.max_flows = []
        for service in self.services_to_run:
            self.max_flows.extend([max_flow for max_flow in service['postprocess_max_flows'] if max_flow not in self.max_flows])

        self.data_type = 'channel'
        if 'forcing' in name:
            self.data_type = 'forcing'
        elif 'land' in name:
            self.data_type = 'land'
        
        if input_files:
            self.input_files = input_files
        else:
            self.input_files, self.service_input_files = self.generate_file_list(reference_time)

    ###################################
    # This method initializes the a configuration class from a s3_file class object by parsing the file path and name to determine the appropriate attributes.
    @classmethod
    def from_s3_file(cls, s3_file, previous_forecasts=0, return_input_files=True, mrf_timestep=3): #TODO:Figure out impact on Corey's stuff to set this to default 3.
        filename = s3_file.key
        input_files = []
        if 'max_flows' in filename:
            matches = re.findall(r"max_flows/(.*)/(\d{8})/\D*_(\d+day_)?(\d{2})_max_flows.*", filename)[0]
            date = matches[1]
            hour = matches[3]
            configuration_name = matches[0]
            reference_time = datetime.datetime.strptime(f"{date[:4]}-{date[-4:][:2]}-{date[-2:]} {hour[-2:]}:00:00", '%Y-%m-%d %H:%M:%S')
            days_match = re.findall(r"(\d+day)", filename)
            if days_match:
                configuration_name = f"{configuration_name}_{days_match[0]}"
        elif 'max_stage' in filename:
            matches = re.findall(r"max_stage/(.*)/(\d{8})/(\d{2})_(\d{2})_ahps_(.*).csv", filename)[0]
            date = matches[1]
            hour = matches[2]
            minute = matches[3]
            configuration_name = matches[0]
            reference_time = datetime.datetime.strptime(f"{date[:4]}-{date[-4:][:2]}-{date[-2:]} {hour[-2:]}:{minute[-2:]}:00", '%Y-%m-%d %H:%M:%S')
        else:
            if 'analysis_assim' in filename:
                matches = re.findall(r"(.*)/nwm.(\d{8})/(.*)/nwm.t(\d{2})z\.(.*)\..*\.tm(.*)\.(.*)\.nc", filename)[0]
            elif 'short_range' in filename or 'medium_range' in filename:
                matches = re.findall(r"(.*)/nwm.(\d{8})/(.*)/nwm.t(\d{2})z\.(.*)\..*\.f(\d{3,5}).(.*)\.nc", filename)[0]
            else:
                raise Exception(f"Configuration not set for {filename}")
            date = matches[1]
            configuration_name = matches[2]
            hour = matches[3]
            reference_time = datetime.datetime.strptime(f"{date[:4]}-{date[-4:][:2]}-{date[-2:]} {hour[-2:]}:00:00", '%Y-%m-%d %H:%M:%S')
            
        return configuration_name, reference_time, s3_file.bucket
    
    ###################################
    # This method generates a complete list of files based on the file pattern data in the admin.db_data_flows_metadata db table.
    # TODO: We should probably abstract the file pattern information in the database to a configuration database table to avoid redundant file patterns.
    def generate_file_list(self, reference_time):
        all_input_files = []
        service_input_files = {}
        for service in self.db_data_flow_metadata:
            service_name = service['service']
            flow_id = service['flow_id']
            file_pattern = service['file_format']
            file_window = service['file_window'] if service['file_window'] != 'None' else ""
            file_window_step = service['file_step'] if service['file_step'] != 'None' else ""
            
            if not file_pattern:
                continue
            
            if 'common/data/model/com/nwm/prod' in file_pattern and (datetime.datetime.today() - datetime.timedelta(29)) > reference_time:
                file_pattern = file_pattern.replace('common/data/model/com/nwm/prod', 'https://storage.googleapis.com/national-water-model')

            if file_window:
                if not file_window_step:
                    file_window_step = None
                reference_dates = pd.date_range(reference_time-isodate.parse_duration(file_window), reference_time, freq=file_window_step)
            else:
                reference_dates = [reference_time]

            tokens = re.findall("{{[a-z]*:[^{]*}}", file_pattern)
            token_dict = {'datetime': [], 'range': []}
            for token in tokens:
                token_key = token.split(":")[0][2:]
                token_value = token.split(":")[1][:-2]

                token_dict[token_key].append(token_value)

            if service_name not in service_input_files:
                service_input_files[service_name] = {}
                
            if flow_id not in service_input_files:
                service_input_files[service_name][flow_id] = []
                
            for reference_date in reference_dates:
                reference_date_file = file_pattern
                reference_date_files = []
                for datetime_token in token_dict['datetime']:
                    reference_date_file = self.parse_datetime_token_value(reference_date_file, reference_date, datetime_token)

                if token_dict['range']:
                    for range_token in token_dict['range']:
                        reference_date_files = self.parse_range_token_value(reference_date_file, range_token)
                else:
                    reference_date_files = [reference_date_file]

                service_input_files[service_name][flow_id].extend(reference_date_files)
                all_input_files.extend(file for file in reference_date_files if file not in all_input_files)

        return all_input_files, service_input_files
    
    ###################################
    # TODO: Might make sense to make this a nested function of the generate_file_list function.
    @staticmethod
    def parse_range_token_value(reference_date_file, range_token):
        range_min = 0
        range_step = 1
        number_format = '%01d'

        parts = range_token.split(',')
        num_parts = len(parts)

        if num_parts == 1:
            range_max = parts[0]
        elif num_parts == 2:
            range_min, range_max = parts
        elif num_parts == 3:
            range_min, range_max, range_step = parts
        elif num_parts == 4:
            range_min, range_max, range_step, number_format = parts
        else:
            raise ValueError("Invalid Token Used")

        try:
            range_min = int(range_min)
            range_max = int(range_max)
            range_step = int(range_step)
        except ValueError:
            raise ValueError("Ranges must be integers")

        new_input_files = []
        for i in range(range_min, range_max, range_step):
            range_value = number_format % i
            new_input_file = reference_date_file.replace(f"{{{{range:{range_token}}}}}", range_value)
            new_input_files.append(new_input_file)

        return new_input_files
    
    ###################################
    # TODO: Might make sense to make this a nested function of the generate_file_list function.
    @staticmethod
    def parse_datetime_token_value(input_file, reference_date, datetime_token):
        og_datetime_token = datetime_token
        if "reftime" in datetime_token:
            reftime = datetime_token.split(",")[0].replace("reftime", "")
            datetime_token = datetime_token.split(",")[-1].replace(" ","")
            arithmetic = reftime[0]
            date_delta_value = int(reftime[1:][:-1])
            date_delta = reftime[1:][-1]

            if date_delta.upper() == "M":
                date_delta = datetime.timedelta(minutes=date_delta_value)
            elif date_delta.upper() == "H":
                date_delta = datetime.timedelta(hours=date_delta_value)
            elif date_delta.upper() == "D":
                date_delta = datetime.timedelta(days=date_delta_value)
            else:
                raise Exception("timedelta is only configured for minutes, hours, and days")

            if arithmetic == "+":
                reference_date = reference_date + date_delta
            else:
                reference_date = reference_date - date_delta
            
        datetime_value = reference_date.strftime(datetime_token)
        new_input_file = input_file.replace(f"{{{{datetime:{og_datetime_token}}}}}", datetime_value)

        return new_input_file
    
    ################################### 
    # This method uses the shared_funcs s3_file class and checks existence on S3 for a full file_list.
    def check_input_files(self, file_threshold=100, retry=True, retry_limit=10):
        total_files = len(self.input_files)
        non_existent_files = []
        for key in self.input_files: #TODO: Set this back up as a list comprehension... not sure how to do that with the class initialization
            file = s3_file(self.input_bucket, key)
            if not file.check_existence():
                non_existent_files.append(file)
        if retry:
            files_ready = False
            retries = 0
            while not files_ready and retries < retry_limit:
                non_existent_files = [file for file in non_existent_files if not file.check_existence()]
                if not non_existent_files:
                    files_ready = True
                else:
                    print(f"Waiting 1 minute until checking for files again. Missing files {non_existent_files}")
                    time.sleep(60)
                    retries += 1
        available_files = []
        for key in self.input_files: #TODO: Set this back up as a list comprehension... not sure how to do that with the class initialization
            file = s3_file(self.input_bucket, key) 
            if file not in non_existent_files:
                available_files.append(file)
        if non_existent_files:
            if (len(available_files) * 100 / total_files) < file_threshold:
                raise Exception(f"Error - Failed to get the following files: {non_existent_files}")
        return True
    
    ###################################
    # This method gathers information for the admin.services table in the database and returns a dictionary of services and their attributes.
    # TODO: Encapsulate this into a view within the database.
    def get_service_metadata(self, specific_service=None, run_only=True, max_flow_method="pipeline"):
        import psycopg2.extras
        service_filter = run_filter = ""
        
        if specific_service:
            service_filter = f"AND service = {specific_service}"
            
        if run_only:
            run_filter = "AND run is True"
            
        max_flow_method_filter = f"AND max_flow_method = '{max_flow_method}'"
            
        connection = database("viz").get_db_connection()
        with connection.cursor(cursor_factory=psycopg2.extras.DictCursor) as cur:
            cur.execute(f"SELECT * FROM admin.services WHERE configuration = '{self.name}' {service_filter} {run_filter} {max_flow_method_filter};")
            column_names = [desc[0] for desc in cur.description]
            response = cur.fetchall()
            cur.close()
        connection.close()
        return list(map(lambda x: dict(zip(column_names, x)), response))
        
    ###################################
    # This method gathers information for the admin.pipeline_data_flows table in the database and returns a dictionary of data source metadata.
    # TODO: Encapsulate this into a view within the database.
    def get_db_data_flow_metadata(self, specific_service=None, run_only=True, max_flow_method="pipeline"):
        import psycopg2.extras
        # Get ingest source data from the database (the ingest_sources table is the authoritative dataset)
        if run_only:
            run_filter = " AND run is True"
            
        max_flow_method_filter = f"AND max_flow_method = '{max_flow_method}'"
        
        connection = database("viz").get_db_connection()
        with connection.cursor(cursor_factory=psycopg2.extras.DictCursor) as cur:
            cur.execute(f"""
                SELECT admin.services.service, flow_id, step, file_format, source_table, target_table, target_keys, file_window, file_step FROM admin.services
                JOIN admin.pipeline_data_flows ON admin.services.service = admin.pipeline_data_flows.service
                WHERE configuration = '{self.name}'{run_filter}  {max_flow_method_filter};
                """)
            column_names = [desc[0] for desc in cur.description]
            response = cur.fetchall()
            cur.close()
        connection.close()
        return list(map(lambda x: dict(zip(column_names, x)), response))
