################################################################################
########################### Viz Initialize Pipeline ############################ 
################################################################################
"""
This function initializes a viz pipeline class, organizes the pipeline metatdata and
input files. It returns a dictionary with all the pipeline info, which it uses to
invoke the aws step function state machine before returning.

Args:
    event (dictionary): The event passed from the state machine.
    context (object): Automatic metadata regarding the invocation.
    
Returns:
    dictionary: The details of the pipeline and files to ingest, to serve as input to the step function.
"""
################################################################################
import datetime
import time
import re
import boto3
import datetime
import time
import os
import json
import isodate
import pandas as pd
from viz_classes import s3_file, database # We use some common custom classes in this lambda layer, in addition to the viz_pipeline and configuration classes defined below.
from viz_lambda_shared_funcs import get_file_tokens, get_formatted_files, gen_dict_extract
import yaml

###################################################################################################################################################
class DuplicatePipelineException(Exception):
    """ my custom exception class """

def lambda_handler(event, context):
    # First, for SNS triggers, check SNS message and only continue if it's a pipeline-initializing file.
    # S3 event filtering doesn't support wildcards, so with the switch to the shared S3 bucket, we needed to add this since all files are now triggering this lambda
    # (lots of false starts, but it only amounts to about $1 a month)
    # Initializing the pipeline class below also does some start-up logic like this based on the event, but I'm keeping this seperate at the very top to keep the timing of those false starts as low as possible.
    if "Records" in event:
        pipeline_iniitializing_files = [
                                        ## ANA ##
                                        "analysis_assim.channel_rt.tm00.conus.nc",
                                        "analysis_assim.forcing.tm00.conus.nc",
                                        "analysis_assim.channel_rt.tm0000.hawaii.nc",
                                        "analysis_assim.forcing.tm00.hawaii.nc",
                                        "analysis_assim.channel_rt.tm00.puertorico.nc",
                                        "analysis_assim.forcing.tm00.puertorico.nc",
                                        "analysis_assim.channel_rt.tm00.alaska.nc",
                                        "analysis_assim.forcing.tm00.alaska.nc",
                                        
                                        ## SRF ##
                                        "short_range.channel_rt.f018.conus.nc",
                                        "short_range.forcing.f018.conus.nc",
                                        "short_range.channel_rt.f04800.hawaii.nc",
                                        "short_range.forcing.f048.hawaii.nc",
                                        "short_range.channel_rt.f048.puertorico.nc",
                                        "short_range.forcing.f048.puertorico.nc",
                                        "short_range.forcing.f015.alaska.nc",
                                        "short_range.channel_rt.f015.alaska.nc",
                                        
                                        ## MRF GFS ##
                                        "medium_range.channel_rt_1.f240.conus.nc",
                                        "medium_range.forcing.f240.conus.nc",
                                        "medium_range.channel_rt.f119.conus.nc",
                                        "medium_range.channel_rt_1.f240.alaska.nc",
                                        "medium_range.forcing.f240.alaska.nc",
                                        
                                        ## MRF NBM ##
                                        "medium_range_blend.channel_rt.f240.conus.nc",
                                        "medium_range_blend.forcing.f240.conus.nc",
                                        "medium_range_blend.channel_rt.f240.alaska.nc",
                                        "medium_range_blend.forcing.f240.alaska.nc",

                                        ## Coastal ##
                                        "analysis_assim_coastal.total_water.tm00.atlgulf.nc",
                                        "analysis_assim_coastal.total_water.tm00.hawaii.nc",
                                        "analysis_assim_coastal.total_water.tm00.puertorico.nc",
                                        "medium_range_coastal.total_water.f240.atlgulf.nc",
                                        "medium_range_blend_coastal.total_water.f240.atlgulf.nc",
                                        "short_range_coastal.total_water.f018.atlgulf.nc",
                                        "short_range_coastal.total_water.f048.puertorico.nc",
                                        "short_range_coastal.total_water.f048.hawaii.nc"
                                        ]
        s3_event = json.loads(event.get('Records')[0].get('Sns').get('Message'))
        if s3_event.get('Records')[0].get('s3').get('object').get('key'):
            s3_key = s3_event.get('Records')[0].get('s3').get('object').get('key')
            if any(suffix in s3_key for suffix in pipeline_iniitializing_files) == False:
                return
            else:
                print(f"Continuing pipeline initialization with Shared Bucket S3 key: {s3_key}")
    
    ###### Initialize the pipeline class & configuration classes ######
    #Initialize the pipeline object - This will parse the lambda event, initialize a configuration, and pull service metadata for that configuration from the viz processing database.
    try:
        pipeline = viz_lambda_pipeline(event) # This does a ton of stuff - see the viz_pipeline class below for details.
        invoke_step_function = pipeline.start_event.get('invoke_step_function') if 'invoke_step_function' in pipeline.start_event else True
    except Exception as e:
        print("Error: Pipeline failed to initialize.")
        raise e

    # If an automated pipeline run, check to see when the last reference time and start time was, and throw an exceptions accordingly
    # TODO: I'm not sure if this is really working. Improve the logic here and in the pipeline init to be smarter about this. e.g. only unfinished pipelines, variable wait time, etc.
    #if pipeline.invocation_type == 'sns' or pipeline.invocation_type == 'lambda':
        #if pipeline.configuration.reference_time <= pipeline.most_recent_ref_time:
            #raise Exception(f"{pipeline.most_recent_ref_time} already ran. Aborting {pipeline.configuration.reference_time}.")
        #minutes_since_last_run = divmod((datetime.datetime.now() - pipeline.most_recent_start).total_seconds(), 60)[0] #Not sure this is working correctly.
        #if minutes_since_last_run < 15:
            #raise DuplicatePipelineException(f"Another {pipeline.configuration.name} pipeline started less than 15 minutes ago. Pausing for 15 minutes.")
        
    pipeline_runs = pipeline.get_pipeline_runs()
    
    # Invoke the step function with the dictionary we've not created.
    step_function_arn = os.environ["STEP_FUNCTION_ARN"]
    if invoke_step_function is True:
        try:
            #Invoke the step function.
            client = boto3.client('stepfunctions')
            for pipeline_run in pipeline_runs:
                ref_time_short = pipeline.configuration.reference_time.strftime("%Y%m%dT%H%M")
                short_config = pipeline_run['configuration'].replace("puertorico", "prvi").replace("hawaii", "hi")
                short_config = short_config.replace("analysis_assim", "ana").replace("short_range", "srf").replace("medium_range", "mrf").replace("replace_route", "rnr")
                short_invoke = pipeline.invocation_type.replace("manual", "man").replace("eventbridge", "bdg")
                pipeline_name = f"{short_invoke}_{short_config}_{ref_time_short}_{datetime.datetime.now().strftime('%d%H%M')}"
                pipeline_run['logging_info'] = {'Timestamp': int(time.time())*1000}
            
                client.start_execution(
                    stateMachineArn = step_function_arn,
                    name = pipeline_name,
                    input= json.dumps(pipeline_run)
                )
            print(f"Invoked: {step_function_arn}")
        except Exception as e:
            print(f"Couldn't invoke - update later. ({e})")
            
    return pipeline_runs

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
    
    def __init__(self, start_event, print_init=True):
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
        
        self.job_type = self.start_event.get('job_type')
        if not self.job_type:
            self.job_type = "auto" if not self.start_event.get('reference_time') else "past_event" # We assume that the specification of a reference_time in the payload correlates to a past_event run.
        
        self.keep_raw = True if self.job_type == "past_event" and self.start_event.get('keep_raw') else False # Keep_raw will determine if a past_event run preserves the raw ingest data tables in the archive schema, or recycles them.
        self.start_time = datetime.datetime.fromtimestamp(time.time())

        if self.start_event.get("detail-type") == "Scheduled Event":
            config, self.reference_time, bucket = s3_file.from_eventbridge(self.start_event)
            self.configuration = configuration(config, reference_time=self.reference_time, input_bucket=bucket)
        # Here is the logic that parses various invocation types / events to determine the configuration and reference time.
        # First we see if a S3 file path is what initialized the function, and use that to determine the appropriate configuration and reference_time.
        elif self.invocation_type == "sns" or self.start_event.get('data_key'):
            self.start_file = s3_file.from_lambda_event(self.start_event)
            configuration_name, self.reference_time, bucket = configuration.from_s3_file(self.start_file)
            self.configuration = configuration(configuration_name, reference_time=self.reference_time, input_bucket=bucket)
        # If a manual invokation_type, we first look to see if a reference_time was specified and use that to determine the configuration.
        elif self.invocation_type == "manual":
            if self.start_event.get('reference_time'):
                self.reference_time = datetime.datetime.strptime(self.start_event.get('reference_time'), '%Y-%m-%d %H:%M:%S')
                self.configuration = configuration(start_event.get('configuration'), reference_time=self.reference_time, input_bucket=start_event.get('bucket'))
            elif self.start_event.get('configuration') and self.start_event.get('configuration') == 'rfc':
                self.configuration = configuration('rfc', reference_time=datetime.datetime.utcnow().replace(second=0, microsecond=0))
            # If no reference time was specified, we get the most recent file available on S3 for the specified configruation, and use that.
            else:
                most_recent_file = s3_file.get_most_recent_from_configuration(configuration_name=start_event.get('configuration'), bucket=start_event.get('bucket'))
                self.start_file = most_recent_file
                configuration_name, self.reference_time, bucket = configuration.from_s3_file(self.start_file)
                self.configuration = configuration(configuration_name, reference_time=self.reference_time, input_bucket=bucket)
        
        # need to figure out this get last run info stuff. Maybe change the queried field from target to configuration
        #self.most_recent_ref_time, self.most_recent_start = self.get_last_run_info()
        self.pipeline_products = self.configuration.products_to_run
        
        self.sql_rename_dict = {} # Empty dictionary for use in past events, if table renames are required. This dictionary is utilized through the pipline as key:value find:replace on SQL files to use tables in the archive schema.
        if self.job_type == "past_event":
            self.organize_rename_dict() #This method organizes input table metadata based on the admin.pipeline_data_flows db table, and updates the sql_rename_dict dictionary if/when needed for past events.
            for word, replacement in self.sql_rename_dict.items():
                self.configuration.configuration_data_flow = json.loads(json.dumps(self.configuration.configuration_data_flow).replace(word, replacement))
                self.configuration.db_ingest_groups = json.loads(json.dumps(self.configuration.db_ingest_groups).replace(word, replacement))
                self.pipeline_products = json.loads(json.dumps(self.pipeline_products).replace(word, replacement))      
            self.sql_rename_dict.update({'1900-01-01 00:00:00': self.reference_time.strftime("%Y-%m-%d %H:%M:%S")}) #Add a reference time for placeholders in sql files
        
        # This allows for filtering FIM runs to a select list of States (this is passed through to FIM Data Prep labmda, where filter is applied)
        if self.start_event.get("states_to_run_fim"):
            for product in self.pipeline_products:
                product['states_to_run'] = self.start_event.get("states_to_run_fim") # only works for fimpact right now
                if product['fim_configs']:
                    for fim_config in product['fim_configs']:
                        fim_config['states_to_run'] = self.start_event.get("states_to_run_fim")
        
        # This allows for skipping ingest step all together - useful if you're testing or re-running and are OK using the ingest data already in the database
        if self.start_event.get("skip_ingest"):
            if self.start_event.get("skip_ingest") is True:
                self.configuration.configuration_data_flow['db_ingest_groups'] = []
        
        # This allows for skipping max flows step alltogether - useful if you're testing or re-running and are OK using the ingest data already in the database
        if self.start_event.get("skip_max_flows"):
            if self.start_event.get("skip_max_flows") is True:
                self.configuration.configuration_data_flow['db_max_flows'] = []
                self.configuration.configuration_data_flow['python_preprocessing'] = []
                
        # This skips running FIM all-together
        if self.start_event.get("skip_fim"):
            if self.start_event.get("skip_fim") is True:
                for product in self.pipeline_products:
                     if product['fim_configs']:
                         product['fim_configs'] = []
        
        # Print a nice tidy summary of the initialized pipeline for logging.
        if print_init:
            self.__print__() 
            
    ###################################
    def get_pipeline_runs(self):
        python_preprocesing_dependent_products = [product for product in self.pipeline_products if product['python_preprocesing_dependent']]
        db_max_flow_dependent_products = [product for product in self.pipeline_products if not product['python_preprocesing_dependent']]

        pipeline_runs = []
        if python_preprocesing_dependent_products and db_max_flow_dependent_products:
            lambda_run = {
                "configuration": f"ppp_{self.configuration.name}",
                "job_type": self.job_type,
                "data_type": self.configuration.data_type,
                "keep_raw": self.keep_raw,
                "reference_time": self.configuration.reference_time.strftime("%Y-%m-%d %H:%M:%S"),
                "configuration_data_flow": {
                    "db_max_flows": [max_flow for max_flow in self.configuration.db_max_flows if max_flow['method']=="lambda"],
                    "python_preprocessing": self.configuration.lambda_input_sets,
                    "db_ingest_groups": [db_ingest for db_ingest in self.configuration.db_ingest_groups if db_ingest['data_origin']=="lambda"]
                },
                "pipeline_products": python_preprocesing_dependent_products,
                "sql_rename_dict": self.sql_rename_dict
            }
            
            db_run = {
                "configuration": self.configuration.name,
                "job_type": self.job_type,
                "data_type": self.configuration.data_type,
                "keep_raw": self.keep_raw,
                "reference_time": self.configuration.reference_time.strftime("%Y-%m-%d %H:%M:%S"),
                "configuration_data_flow": {
                    "db_max_flows": [max_flow for max_flow in self.configuration.db_max_flows if max_flow['method']=="database"],
                    "python_preprocessing": [],
                    "db_ingest_groups": [db_ingest for db_ingest in self.configuration.db_ingest_groups if db_ingest['data_origin']=="raw"]
                },
                "pipeline_products": db_max_flow_dependent_products,
                "sql_rename_dict": self.sql_rename_dict
            }
            pipeline_runs = [lambda_run, db_run]
        else:
            pipeline_runs = [{
                "configuration": self.configuration.name,
                "job_type": self.job_type,
                "data_type": self.configuration.data_type,
                "keep_raw": self.keep_raw,
                "reference_time": self.configuration.reference_time.strftime("%Y-%m-%d %H:%M:%S"),
                "configuration_data_flow": self.configuration.configuration_data_flow,
                "pipeline_products": self.pipeline_products,
                "sql_rename_dict": self.sql_rename_dict
            }]
        
        return pipeline_runs
    
    ###################################
    # This method gathers information on the last pipeline run for the given configuration
    # TODO: This should totally be in the configuration class... and we should abstract a view to access this information.
    def get_last_run_info(self):
        last_run_info = {}
        target_table = [data_flow['target_table'] for data_flow in self.configuration.configuration_data_flow['db_ingest_groups']][0]
        viz_db = database(db_type="viz")
        with viz_db.get_db_connection() as connection:
            last_run_info[target_table] = {}
            cur = connection.cursor()
            cur.execute(f"""
                SELECT max(reference_time) as reference_time, last_update
                FROM (SELECT max(update_time) as last_update from admin.ingest_status a
                        WHERE target = '{target_table}' and status = 'Import Started') as last_start
                JOIN admin.ingest_status a ON last_start.last_update = a.update_time
                GROUP BY last_update
            """)
            try:
                return cur.fetchone()[0], ur.fetchone()[1]
            except: #if nothing logged in db, return generic datetimes in the past
                return datetime.datetime(2000, 1, 1, 0, 0, 0), datetime.datetime(2000, 1, 1, 0, 0, 0)
    
    ###################################
    def organize_rename_dict(self):
        sql_rename_dict = {}
        ref_prefix = f"ref_{self.configuration.reference_time.strftime('%Y%m%d_%H%M_')}" # replace invalid characters as underscores in ref time.
        
        for target_table in list(gen_dict_extract("target_table", self.configuration.configuration_data_flow)):
            target_table_schema = target_table.split(".")[0]
            target_table_name = target_table.split(".")[1]
            new_table_name = f"{ref_prefix}{target_table_schema}_{target_table_name}"
            sql_rename_dict[target_table] = f"archive.{new_table_name}"
        
        for product in self.pipeline_products:
            for target_table in list(gen_dict_extract("target_table", product)):
                if type(target_table) != list:
                    target_table = [target_table]
                for table in target_table:
                    target_table_schema = table.split(".")[0]
                    target_table_name = table.split(".")[1]
                    new_table_name = f"{ref_prefix}{target_table_schema}_{target_table_name}"
                    sql_rename_dict[table] = f"archive.{new_table_name}"
            
        self.sql_rename_dict = sql_rename_dict
    
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
#   - short_range - A NWM short_range forecast... used for services like srf_18hr_max_high_flow_magnitude, srf_18hr_high_water_arrival_time, srf_48hr_max_inundation, etc.
#   - medium_range_mem1 - The first ensemble member of a NWM medium_range forecast... used for services like mrf_gfs_10day_max_high_flow_magnitude, mrf_gfs_10day_high_water_arrival_time, mrf_gfs_max_inundation, etc.
#   - ahps - The ahps RFC forecast and location data (currently gathered from the WRDS forecast and location APIs) that are required to produce rfc_max_forecast service data.
#   - replace_route - The ourput of the replace and route model that are required to produce the rfc_5day_max_downstream streamflow and inundation services.

class configuration:
    def __init__(self, name, reference_time=None, input_bucket=None): #TODO: Futher build out ref time range.
        self.name = name
        self.reference_time = reference_time
        self.input_bucket = input_bucket
        self.products_to_run = self.get_product_metadata()
        self.get_configuration_data_flow()  # Setup datasets dictionaries for general configuration
        
        for product in self.products_to_run:  # Remove configuration data flow keys from product info to be cleaner
            product.pop('db_max_flows', 'No Key found')
            product.pop('python_preprocessing', 'No Key found')
            product.pop('ingest_files', 'No Key found')

        self.data_type = 'channel'
        if 'forcing' in name:
            self.data_type = 'forcing'
        elif 'land' in name:
            self.data_type = 'land'

    ###################################
    # This method initializes the a configuration class from a s3_file class object by parsing the file path and name to determine the appropriate attributes.
    @classmethod
    def from_s3_file(cls, s3_file):
        filename = s3_file.key
        if 'max_flows' in filename:
            matches = re.findall(r"max_flows/(.*)/(\d{8})/\D*_(\d+day_)?(\d{2})_max_flows.*", filename)[0]
            date = matches[1]
            hour = matches[3]
            configuration_name = matches[0]
            reference_time = datetime.datetime.strptime(f"{date[:4]}-{date[-4:][:2]}-{date[-2:]} {hour[-2:]}:00:00", '%Y-%m-%d %H:%M:%S')
        elif 'max_stage' in filename:
            matches = re.findall(r"max_stage/(.*)/(\d{8})/(\d{2})_(\d{2})_ahps_(.*).csv", filename)[0]
            date = matches[1]
            hour = matches[2]
            minute = matches[3]
            configuration_name = "rfc"
            reference_time = datetime.datetime.strptime(f"{date[:4]}-{date[-4:][:2]}-{date[-2:]} {hour[-2:]}:{minute[-2:]}:00", '%Y-%m-%d %H:%M:%S')
        elif 'replace_route' in filename:
            matches = re.findall(r"(.*)/(\d{8})/wrf_hydro/replace_route.t(\d{2})z.medium_range.channel_rt.f(\d{3,5}).(.*)\.nc", filename)[0]
            configuration_name = 'replace_route'
            date = matches[1]
            hour = matches[2]
            reference_time = datetime.datetime.strptime(f"{date[:4]}-{date[-4:][:2]}-{date[-2:]} {hour[-2:]}:00:00", '%Y-%m-%d %H:%M:%S')
        else:
            if 'analysis_assim' in filename:
                matches = re.findall(r"(.*)/nwm.(\d{8})/(.*)/nwm.t(\d{2})z\.(.*)\..*\.tm(.*)\.(.*)\.nc", filename)[0]
            elif 'short_range' in filename or 'medium_range' in filename:
                matches = re.findall(r"(.*)/nwm.(\d{8})/(.*)/nwm.t(\d{2})z\.(.*)\..*\.f(\d{3,5}).(.*)\.nc", filename)[0]
            else:
                raise Exception(f"Configuration not set for {filename}")
            date = matches[1]
            configuration_name = matches[2].replace('_atlgulf', '')
            hour = matches[3]
            reference_time = datetime.datetime.strptime(f"{date[:4]}-{date[-4:][:2]}-{date[-2:]} {hour[-2:]}:00:00", '%Y-%m-%d %H:%M:%S')
            
        return configuration_name, reference_time, s3_file.bucket
    
    ###################################
    # This method generates a complete list of files based on the file pattern data in the admin.db_data_flows_metadata db table.
    # TODO: We should probably abstract the file pattern information in the database to a configuration database table to avoid redundant file patterns.
    def generate_ingest_groups_file_list(self, file_groups, data_origin="raw"):
            
        target_table_input_files = {}
        ingest_sets = {}
        for file_group in file_groups:

            file_pattern = file_group['file_format']
            file_window = file_group['file_window'] if file_group['file_window'] != 'None' else ""
            file_window_step = file_group['file_step'] if file_group['file_step'] != 'None' else ""
            target_table = file_group['target_table'] if file_group['target_table'] != 'None' else ""
            target_keys = file_group['target_keys'] if file_group['target_keys'] != 'None' else ""
            target_cols = file_group.get('target_cols', self.get_default_target_cols(file_pattern))
            target_keys = target_keys[1:-1].replace(" ","").split(",")
            dependent_on = file_group['dependent_on'] if file_group.get('dependent_on') else ""
            
            if target_table not in target_table_input_files:
                target_table_input_files[target_table] = {
                    's3_keys': [],
                    'target_keys': [],
                    'target_cols': []
                }
                
            new_keys = [key for key in target_keys if key not in target_table_input_files[target_table]['target_keys'] and key]
            target_table_input_files[target_table]['target_keys'].extend(new_keys)
            nws_cols = [var for var in target_cols if var not in target_table_input_files[target_table]['target_cols'] and var]
            target_table_input_files[target_table]['target_cols'].extend(nws_cols)

            if file_window:
                if not file_window_step:
                    file_window_step = None
                reference_dates = pd.date_range(self.reference_time-isodate.parse_duration(file_window), self.reference_time, freq=file_window_step)
            else:
                reference_dates = [self.reference_time]

            token_dict = get_file_tokens(file_pattern)
    
            for reference_date in reference_dates:
                reference_date_files = get_formatted_files(file_pattern, token_dict, reference_date)

                new_files = [file for file in reference_date_files if file not in target_table_input_files[target_table]['s3_keys']]
                target_table_input_files[target_table]['s3_keys'].extend(new_files)

        ingest_sets = []
        for target_table, target_table_metadata in target_table_input_files.items():
            target_keys = f"({','.join(target_table_metadata['target_keys'])})"
            index_name = f"idx_{target_table.split('.')[-1:].pop()}_{target_keys.replace(',', '_')[1:-1]}"

            ingest_file = target_table_metadata["s3_keys"][0]
            if "rnr" in ingest_file:
                bucket=os.environ['RNR_DATA_BUCKET']
            elif "viz_ingest" in ingest_file or "max_" in ingest_file:
                bucket=os.environ['PYTHON_PREPROCESSING_BUCKET']
            else:
                bucket = self.input_bucket
            
            ingest_sets.append({
                "target_table": target_table, 
                "target_cols": target_table_metadata["target_cols"],
                "ingest_datasets": target_table_metadata["s3_keys"], 
                "index_columns": target_keys,
                "index_name": index_name,
                "bucket": bucket,
                "keep_flows_at_or_above": float(os.environ['INGEST_FLOW_THRESHOLD']),
                "data_origin": data_origin,
                "dependent_on": dependent_on
            })
            
        return ingest_sets
    
    @staticmethod
    def get_default_target_cols(file_pattern):
        default_target_cols = []
        if 'channel_rt' in file_pattern:
            default_target_cols = ['feature_id', 'forecast_hour', 'streamflow']
        
        return default_target_cols
        
    ###################################
    def generate_python_preprocessing_file_list(self, file_groups):
        python_preprocesing_ingest_sets = []
        db_ingest_sets = []
        for file_group in file_groups:
            product = file_group['product'] 
            config = file_group['config'] if file_group.get('config') else None
            lambda_ram = file_group['lambda_ram'] if file_group.get('lambda_ram') else None
            output_file = file_group['output_file']
            
            token_dict = get_file_tokens(output_file)
            formatted_output_file = get_formatted_files(output_file, token_dict, self.reference_time)[0]
            
            python_preprocesing_file_set = self.generate_ingest_groups_file_list([file_group])
            python_preprocesing_ingest_sets.append({
                "fileset": python_preprocesing_file_set[0]['ingest_datasets'],
                "fileset_bucket": python_preprocesing_file_set[0]['bucket'],
                "product": product,
                "config": config,
                "lambda_ram": lambda_ram,
                "output_file": formatted_output_file,
                "output_file_bucket": os.environ['PYTHON_PREPROCESSING_BUCKET'],
            })
            
            db_ingest_file_groups = [{
                'file_format': formatted_output_file, 
                'file_step': "", 
                'file_window': "", 
                'target_table': file_group['target_table'], 
                'target_keys': file_group['target_keys']
            }]
            db_ingest_file_set = self.generate_ingest_groups_file_list(db_ingest_file_groups, data_origin="lambda")[0]
            db_ingest_sets.append(db_ingest_file_set)
    
        return python_preprocesing_ingest_sets, db_ingest_sets
    
    ###################################
    # This method gathers information for the admin.services table in the database and returns a dictionary of services and their attributes.
    def get_product_metadata(self, specific_products=None, run_only=True):
        all_product_metadata = []
        pipeline_run_time = self.reference_time.strftime("%H:%M")
        pipeline_run_date = self.reference_time.strftime("%Y%m%d")
        pipeline_run_hour = self.reference_time.strftime("%H")
        
        product_configs_dir = os.path.join('product_configs', self.name)
        configuration_product_ymls = os.listdir(product_configs_dir)
        for configuration_product_yml in configuration_product_ymls:
            yml_path = os.path.join(product_configs_dir, configuration_product_yml)

            product_stream = open(yml_path, 'r')
            product_metadata = yaml.safe_load(product_stream)
            product_name = product_metadata['product']
            
            if product_metadata.get("run_times"):
                all_run_times = []
                for run_time in product_metadata.get("run_times"):
                    if "*:" in run_time:
                        all_run_times.extend([f"{hour:02d}:{run_time.split(':')[-1]}" for hour in range(24)])
                    else:
                        all_run_times.append(run_time)
                
                if pipeline_run_time not in all_run_times:
                    continue
            
            if product_metadata.get("raster_input_files"):
                product_metadata['raster_input_files']['bucket'] = self.input_bucket

            raster_output_bucket = os.environ['RASTER_OUTPUT_BUCKET']
            raster_output_prefix = os.environ['RASTER_OUTPUT_PREFIX']
            product_metadata['raster_outputs'] = {}
            product_metadata['raster_outputs']['output_bucket'] = ""
            product_metadata['raster_outputs']['output_raster_workspaces'] = []
            if product_metadata['product_type'] == "raster":
                product_metadata['raster_outputs']['output_bucket'] = raster_output_bucket
                product_metadata['raster_outputs']['output_raster_workspaces'].append({product_name: f"{raster_output_prefix}/{product_name}/{pipeline_run_date}/{pipeline_run_hour}/workspace"})
            
            if not product_metadata.get("fim_configs"):
                product_metadata['fim_configs'] = []
            else:
                for fim_config in product_metadata['fim_configs']:
                    fim_config_name = fim_config['name']
                    if not fim_config.get('sql_file'):
                        fim_config['sql_file'] = fim_config_name
                    
                    if hasattr(self, "states_to_run_fim"):
                        fim_config['states_to_run'] = self.states_to_run_fim

                    if fim_config.get('preprocess'):
                        fim_config['preprocess']['output_file_bucket'] = os.environ['PYTHON_PREPROCESSING_BUCKET']
                        fim_config['preprocess']['fileset_bucket'] = self.input_bucket

                    if fim_config['fim_type'] == "coastal":
                        if not product_metadata['raster_outputs'].get('output_bucket'):
                            product_metadata['raster_outputs']['output_bucket'] = raster_output_bucket
                        product_metadata['raster_outputs']['output_raster_workspaces'].append({fim_config_name: f"{raster_output_prefix}/{product_name}/{fim_config_name}/{pipeline_run_date}/{pipeline_run_hour}/workspace"})
            
            if not product_metadata.get("postprocess_sql"):
                product_metadata['postprocess_sql'] = []
            
            if not product_metadata.get("product_summaries"):
                product_metadata['product_summaries'] = []
            
            if not product_metadata.get("services"):
                product_metadata['services'] = []
            
            all_product_metadata.append(product_metadata)
            
        if run_only:
            all_product_metadata = [product for product in all_product_metadata if product['run']]
            
        if specific_products:
            all_product_metadata = [product for product in all_product_metadata if product['name'] in specific_products]
            
        return all_product_metadata
        
    def get_configuration_data_flow(self):
        self.db_max_flows = []
        self.python_preprocessing = []
        self.ingest_groups = []
        
        for product in self.products_to_run:
            product['python_preprocesing_dependent'] = False
            if product.get('db_max_flows'):
                self.db_max_flows.extend([max_flow for max_flow in product['db_max_flows'] if max_flow not in self.db_max_flows])
                
            if product.get('python_preprocessing'):
                product['python_preprocesing_dependent'] = True
                self.python_preprocessing.extend([python_preprocess for python_preprocess in product['python_preprocessing'] if python_preprocess not in self.python_preprocessing])
                
            if product.get('ingest_files'):
                self.ingest_groups.extend([ingest_group for ingest_group in product['ingest_files'] if ingest_group not in self.ingest_groups])
                
        self.db_ingest_groups = self.generate_ingest_groups_file_list(self.ingest_groups)
        
        self.lambda_input_sets, lambda_derived_db_ingest_sets = self.generate_python_preprocessing_file_list(self.python_preprocessing)
        self.db_ingest_groups.extend(lambda_derived_db_ingest_sets)
        
        self.configuration_data_flow = {
            "db_max_flows": self.db_max_flows,
            "db_ingest_groups": self.db_ingest_groups,
            "python_preprocessing": self.lambda_input_sets
        }
        
        return