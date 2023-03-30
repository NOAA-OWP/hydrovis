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
import collections
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
from botocore.exceptions import ClientError
from viz_classes import s3_file, database # We use some common custom classes in this lambda layer, in addition to the viz_pipeline and configuration classes defined below.
import yaml

###################################################################################################################################################
class DuplicatePipelineException(Exception):
    """ my custom exception class """

def lambda_handler(event, context):
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
    if pipeline.invocation_type == 'sns' or pipeline.invocation_type == 'lambda':
        if pipeline.configuration.reference_time <= pipeline.most_recent_ref_time:
            raise Exception(f"{pipeline.most_recent_ref_time} already ran. Aborting {pipeline.configuration.reference_time}.")
        minutes_since_last_run = divmod((datetime.datetime.now() - pipeline.most_recent_start).total_seconds(), 60)[0] #Not sure this is working correctly.
        if minutes_since_last_run < 15:
            raise DuplicatePipelineException(f"Another {pipeline.configuration.name} pipeline started less than 15 minutes ago. Pausing for 15 minutes.")
        
    pipeline_runs = pipeline.check_for_multiple_pipeline_runs()
    
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
    
    def __init__(self, start_event, print_init=True, step=None):
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
            self.configuration = configuration(config, reference_time=self.reference_time, input_bucket=bucket, step=step)
        # Here is the logic that parses various invocation types / events to determine the configuration and reference time.
        # First we see if a S3 file path is what initialized the function, and use that to determine the appropriate configuration and reference_time.
        elif self.invocation_type == "sns" or self.start_event.get('data_key'):
            self.start_file = s3_file.from_lambda_event(self.start_event)
            configuration_name, self.reference_time, bucket = configuration.from_s3_file(self.start_file)
            self.configuration = configuration(configuration_name, reference_time=self.reference_time, input_bucket=bucket, step=step)
        # If a manual invokation_type, we first look to see if a reference_time was specified and use that to determine the configuration.
        elif self.invocation_type == "manual":
            if self.start_event.get('reference_time'):
                self.reference_time = datetime.datetime.strptime(self.start_event.get('reference_time'), '%Y-%m-%d %H:%M:%S')
                self.configuration = configuration(start_event.get('configuration'), reference_time=self.reference_time, input_bucket=start_event.get('bucket'), step=step)
            # If no reference time was specified, we get the most recent file available on S3 for the specified configruation, and use that.
            else:
                most_recent_file = s3_file.get_most_recent_from_configuration(configuration_name=start_event.get('configuration'), bucket=start_event.get('bucket'))
                self.start_file = most_recent_file
                configuration_name, self.reference_time, bucket = configuration.from_s3_file(self.start_file)
                self.configuration = configuration(configuration_name, reference_time=self.reference_time, input_bucket=bucket, step=step)
        
        # Get some other useful attributes for the pipeline, given the attributes we now have.
        self.most_recent_ref_time, self.most_recent_start = self.get_last_run_info()
        self.pipeline_products = self.configuration.products_to_run
        
        self.sql_rename_dict = {} # Empty dictionary for use in past events, if table renames are required. This dictionary is utilized through the pipline as key:value find:replace on SQL files to use tables in the archive schema.
        if self.job_type == "past_event":
            self.organize_rename_dict() #This method organizes input table metadata based on the admin.pipeline_data_flows db table, and updates the sql_rename_dict dictionary if/when needed for past events.
        
        # Print a nice tidy summary of the initialized pipeline for logging.
        if print_init:
            self.__print__() 
            
    ###################################
    def check_for_multiple_pipeline_runs(self):
        lambda_max_flow_dependent_products = [product for product in self.pipeline_products if product['lambda_max_flow_dependent']]
        db_max_flow_dependent_products = [product for product in self.pipeline_products if not product['lambda_max_flow_dependent']]

        pipeline_runs = []
        if lambda_max_flow_dependent_products and db_max_flow_dependent_products:
            lambda_run = {
                "configuration": f"lmf_{self.configuration.name}",
                "job_type": self.job_type,
                "data_type": self.configuration.data_type,
                "keep_raw": self.keep_raw,
                "reference_time": self.configuration.reference_time.strftime("%Y-%m-%d %H:%M:%S"),
                "configuration_data_flow": {
                    "db_max_flows": [max_flow for max_flow in self.configuration.db_max_flows if max_flow['method']=="lambda"],
                    "lambda_max_flows": self.configuration.lambda_input_sets,
                    "db_ingest_groups": []
                },
                "pipeline_products": lambda_max_flow_dependent_products,
                "sql_rename_dict": self.sql_rename_dict
            }
            
            db_run = {
                "configuration": f"dmf_{self.configuration.name}",
                "job_type": self.job_type,
                "data_type": self.configuration.data_type,
                "keep_raw": self.keep_raw,
                "reference_time": self.configuration.reference_time.strftime("%Y-%m-%d %H:%M:%S"),
                "configuration_data_flow": {
                    "db_max_flows": [max_flow for max_flow in self.configuration.db_max_flows if max_flow['method']=="database"],
                    "lambda_max_flows": [],
                    "db_ingest_groups": self.configuration.db_ingest_groups
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
    def organize_rename_dict(self, run_only=True): 
        
        def gen_dict_extract(key, var):
            if hasattr(var,'items'):
                for k, v in var.items():
                    if k == key:
                        yield v
                    if isinstance(v, dict):
                        for result in gen_dict_extract(key, v):
                            yield result
                    elif isinstance(v, list):
                        for d in v:
                            for result in gen_dict_extract(key, d):
                                yield result
        
        sql_rename_dict = {}
        ref_prefix = f"ref_{self.configuration.reference_time.strftime('%Y%m%d_%H%M_')}" # replace invalid characters as underscores in ref time.
        
        for target_table in gen_dict_extract("target_table", self.configuration.configuration_data_flow):
            target_table_name = target_table.split(".")[1]
            new_table_name = f"{ref_prefix}{target_table_name}"
            sql_rename_dict[target_table] = f"archive.{new_table_name}"
        
        for product in self.pipeline_products:
            for target_table in gen_dict_extract("target_table", product):
                target_table_name = target_table.split(".")[1]
                new_table_name = f"{ref_prefix}{target_table_name}"
                sql_rename_dict[target_table] = f"archive.{new_table_name}"
            
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
#   - short_range - A NWM short_range forecast... used for services like srf_max_high_flow_magnitude, srf_high_water_arrival_time, srf_max_inundation, etc.
#   - medium_range_mem1 - The first ensemble member of a NWM medium_range forecast... used for services like mrf_max_high_flow_magnitude, mrf_high_water_arrival_time, mrf_max_inundation, etc.
#   - ahps - The ahps RFC forecast and location data (currently gathered from the WRDS forecast and location APIs) that are required to produce rfc_max_stage service data.
#   - replace_route - The ourput of the replace and route model that are required to produce the rfc_5day_max_downstream streamflow and inundation services.

class configuration:
    def __init__(self, name, reference_time=None, input_bucket=None, input_files=None, step=None): #TODO: Futher build out ref time range.
        self.name = name
        self.reference_time = reference_time
        self.input_bucket = input_bucket
        self.products_to_run = self.get_product_metadata()
        self.get_configuration_data_flow()  # Setup datasets dictionaries for general configuration
        
        for product in self.products_to_run:  # Remove configuration data flow keys from product info to be cleaner
            product.pop('db_max_flows', 'No Key found')
            product.pop('lambda_max_flows', 'No Key found')
            product.pop('ingest_files', 'No Key found')

        self.data_type = 'channel'
        if 'forcing' in name:
            self.data_type = 'forcing'
        elif 'land' in name:
            self.data_type = 'land'

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
        elif 'max_stage' in filename:
            matches = re.findall(r"max_stage/(.*)/(\d{8})/(\d{2})_(\d{2})_ahps_(.*).csv", filename)[0]
            date = matches[1]
            hour = matches[2]
            minute = matches[3]
            configuration_name = matches[0]
            reference_time = datetime.datetime.strptime(f"{date[:4]}-{date[-4:][:2]}-{date[-2:]} {hour[-2:]}:{minute[-2:]}:00", '%Y-%m-%d %H:%M:%S')
        elif 'max_elevs' in filename:	
            matches = re.findall(r"max_elevs/(.*)/(\d{8})/\D*_(mem\d_)?(\d+day_)?(\d{2})_max_elevs.*", filename)[0]
            date = matches[1]
            hour = matches[-1]	
            configuration_name = matches[0]	
            reference_time = datetime.datetime.strptime(f"{date[:4]}-{date[-4:][:2]}-{date[-2:]} {hour[-2:]}:00:00", '%Y-%m-%d %H:%M:%S')
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
    def generate_file_list(self, file_groups):
        all_input_files = []
        target_table_input_files = {}
        ingest_sets = {}
        for file_group in file_groups:

            file_pattern = file_group['file_format']
            file_window = file_group['file_window'] if file_group['file_window'] != 'None' else ""
            file_window_step = file_group['file_step'] if file_group['file_step'] != 'None' else ""
            target_table = file_group['target_table'] if file_group['target_table'] != 'None' else ""
            target_keys = file_group['target_keys'] if file_group['target_keys'] != 'None' else ""
            target_keys = target_keys[1:-1].replace(" ","").split(",")
            
            if target_table not in target_table_input_files:
                target_table_input_files[target_table] = {}
                target_table_input_files[target_table]['s3_keys'] = []
                target_table_input_files[target_table]['target_keys'] = []
                
            new_keys = [key for key in target_keys if key not in target_table_input_files[target_table]['target_keys'] and key]
            target_table_input_files[target_table]['target_keys'].extend(new_keys)
            
            if 'common/data/model/com/nwm/prod' in file_pattern and (datetime.datetime.today() - datetime.timedelta(29)) > self.reference_time:
                file_pattern = file_pattern.replace('common/data/model/com/nwm/prod', 'https://storage.googleapis.com/national-water-model')

            if file_window:
                if not file_window_step:
                    file_window_step = None
                reference_dates = pd.date_range(self.reference_time-isodate.parse_duration(file_window), self.reference_time, freq=file_window_step)
            else:
                reference_dates = [self.reference_time]

            tokens = re.findall("{{[a-z]*:[^{]*}}", file_pattern)
            token_dict = {'datetime': [], 'range': []}
            for token in tokens:
                token_key = token.split(":")[0][2:]
                token_value = token.split(":")[1][:-2]

                token_dict[token_key].append(token_value)
                
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

                new_files = [file for file in reference_date_files if file not in target_table_input_files[target_table]['s3_keys']]
                target_table_input_files[target_table]['s3_keys'].extend(new_files)

        ingest_sets = []
        for target_table, target_table_metadata in target_table_input_files.items():
            target_keys = f"({','.join(target_table_metadata['target_keys'])})"
            index_name = f"idx_{target_table.split('.')[-1:].pop()}_{target_keys.replace(', ', '_')[1:-1]}"
            
            ingest_sets.append({
                "target_table": target_table, 
                "ingest_datasets": target_table_metadata["s3_keys"], 
                "index_columns": target_keys,
                "index_name": index_name,
                "reference_time": self.reference_time.strftime("%Y-%m-%d %H:%M:%S"),
                "bucket": self.input_bucket,
                "keep_flows_at_or_above": float(os.environ['INGEST_FLOW_THRESHOLD']),
            })
            
        return ingest_sets
    
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
    def get_product_metadata(self, specific_products=None, run_only=True):
        all_product_metadata = []
        pipeline_run_time = int(self.reference_time.strftime("%H"))
        
        configuration_product_ymls = os.listdir(self.name)
        for configuration_product_yml in configuration_product_ymls:
            yml_path = os.path.join(self.name, configuration_product_yml)

            product_stream = open(yml_path, 'r')
            product_metadata = yaml.safe_load(product_stream)
            
            if product_metadata.get("run_times"):
                if pipeline_run_time not in product_metadata.get("run_times"):
                    continue
            
            all_product_metadata.append(product_metadata)
            
        if run_only:
            all_product_metadata = [product for product in all_product_metadata if product['run']]
            
        if specific_products:
            all_product_metadata = [product for product in all_product_metadata if product['name'] in specific_products]
            
        return all_product_metadata
        
    def get_configuration_data_flow(self):
        self.db_max_flows = []
        self.lambda_max_flows = []
        self.ingest_groups = []
        
        for product in self.products_to_run:
            product['lambda_max_flow_dependent'] = False
            if product.get('db_max_flows'):
                self.db_max_flows.extend([max_flow for max_flow in product['db_max_flows'] if max_flow not in self.db_max_flows])
                
            if product.get('lambda_max_flows'):
                product['lambda_max_flow_dependent'] = True
                self.lambda_max_flows.extend([max_flow for max_flow in product['lambda_max_flows'] if max_flow not in self.lambda_max_flows])
                
            if product.get('ingest_files'):
                self.ingest_groups.extend([max_flow for max_flow in product['ingest_files'] if max_flow not in self.ingest_groups])
                
        self.lambda_input_sets = self.generate_file_list(self.lambda_max_flows)
        self.db_ingest_groups = self.generate_file_list(self.ingest_groups)
        
        self.configuration_data_flow = {
            "db_max_flows": self.db_max_flows,
            "db_ingest_groups": self.db_ingest_groups,
            "lambda_max_flows": self.lambda_input_sets
        }
        
        return