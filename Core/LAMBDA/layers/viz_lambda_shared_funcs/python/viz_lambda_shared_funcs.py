import os
import boto3
import base64
import json
import time
import re
import urllib.parse
from datetime import datetime, timedelta
from botocore.exceptions import ClientError

class MissingS3FileException(Exception):
    """ my custom exception class """

def get_secret_password(secret_name, region_name, key):
    """
        Gets a password from a sercret stored in AWS secret manager.

        Args:
            secret_name(str): The name of the secret
            region_name(str): The name of the region

        Returns:
            password(str): The text of the password
    """

    # Create a Secrets Manager client
    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name=region_name
    )

    # In this sample we only handle the specific exceptions for the 'GetSecretValue' API.
    # See https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_GetSecretValue.html
    # We rethrow the exception by default.

    try:
        get_secret_value_response = client.get_secret_value(
            SecretId=secret_name
        )
    except ClientError as e:
        if e.response['Error']['Code'] == 'DecryptionFailureException':
            # Secrets Manager can't decrypt the protected secret text using the provided KMS key.
            # Deal with the exception here, and/or rethrow at your discretion.
            raise e
        elif e.response['Error']['Code'] == 'InternalServiceErrorException':
            # An error occurred on the server side.
            # Deal with the exception here, and/or rethrow at your discretion.
            raise e
        elif e.response['Error']['Code'] == 'InvalidParameterException':
            # You provided an invalid value for a parameter.
            # Deal with the exception here, and/or rethrow at your discretion.
            raise e
        elif e.response['Error']['Code'] == 'InvalidRequestException':
            # You provided a parameter value that is not valid for the current state of the resource.
            # Deal with the exception here, and/or rethrow at your discretion.
            raise e
        elif e.response['Error']['Code'] == 'ResourceNotFoundException':
            # We can't find the resource that you asked for.
            # Deal with the exception here, and/or rethrow at your discretion.
            raise e
        else:
            print(e)
            raise e
    else:
        # Decrypts secret using the associated KMS CMK.
        # Depending on whether the secret is a string or binary, one of these fields will be populated.
        if 'SecretString' in get_secret_value_response:
            secret = get_secret_value_response['SecretString']
            j = json.loads(secret)
            password = j[key]
        else:
            decoded_binary_secret = base64.b64decode(get_secret_value_response['SecretBinary'])
            print("password binary:" + decoded_binary_secret)
            password = decoded_binary_secret.password

        return password


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


def check_s3_fileset(bucket, input_files, file_threshold=100, retry=True, retry_limit=10):
    """
        Checks a full set of s3 files for availability and returns the ready files.

        Args:
            bucket(str): The S3 bucket
            input_files(list): The list of input files to check
            file_threshold (int): The percent required of input_file to proceed
            retry (boolean): Should the function retry on missing files
            retry_limit (int): The number of retries to attempt on missing files

        Returns:
            ready_files (list): A list of available S3 files.
    """
    total_files = len(input_files)
    non_existent_files = [file for file in input_files if not check_s3_file_existence(bucket, file)]

    if retry:
        files_ready = False
        retries = 0
        while not files_ready and retries < retry_limit:
            non_existent_files = [file for file in non_existent_files if not check_s3_file_existence(bucket, file)]
            
            if not non_existent_files:
                files_ready = True
            else:
                print(f"Waiting 1 minute until checking for files again. Missing files {non_existent_files}")
                time.sleep(60)
                retries += 1

    available_files = [file for file in input_files if file not in non_existent_files]
        
    if non_existent_files:
        if (len(available_files) * 100 / total_files) < file_threshold:
            raise Exception(f"Error - Failed to get the following files: {non_existent_files}")
    
    return available_files


def parse_s3_sns_message(event):
    """
        Parses the event json string passed from a S3 file notification SNS topic trigger, to return the data bucket
        and key.

        Args:
            event(str): The event passed from triggering SNS topic.

        Returns:
            data_key(str): The key(path) of the triggering S3 file.
            data_bucket(str): The S3 bucket of the triggering S3 file.
    """
    print("Parsing lambda event to get S3 key and bucket.")
    if "Records" in event:
        message = json.loads(event["Records"][0]['Sns']['Message'])
        data_key = urllib.parse.unquote_plus(message["Records"][0]['s3']['object']['key'], encoding='utf-8')
        data_bucket = message["Records"][0]['s3']['bucket']['name']
    else:
        data_key = event['data_key']
        data_bucket = event['data_bucket']
    return data_key, data_bucket


def get_most_recent_s3_file(bucket, configuration):
    """
        Gets the most recent s3 file of a particular configuration.

        Args:
            bucket (string): The s3 bucket to search through.
            configuration (string): The configuration to search. Valid values are replace_route
                or any of the used NWM configurations ('short_range', 'medium_range_mem1', etc.)

        Returns:
            file (string): The path to the most recent S3 object that meets the criteria.
    """
    s3 = boto3.client('s3')

    # Set the S3 prefix based on the confiuration
    def get_s3_prefix(configuration, date):
        if configuration == 'replace_route':
            prefix = f"replace_route/{date}/wrf_hydro/"
        elif configuration == 'ahps':
            prefix = f"max_stage/ahps/{date}/"
        else:
            nwm_dataflow_version = os.environ.get("NWM_DATAFLOW_VERSION") if os.environ.get("NWM_DATAFLOW_VERSION") else "prod"
            prefix = f"common/data/model/com/nwm/{nwm_dataflow_version}/nwm.{date}/{configuration}/"

        return prefix

    # Get all S3 files that match the bucket / prefix
    def list_s3_files(bucket, prefix):
        files = []
        paginator = s3.get_paginator('list_objects_v2')
        for result in paginator.paginate(Bucket=bucket, Prefix=prefix):
            for key in result['Contents']:
                # Skip folders
                if not key['Key'].endswith('/'):
                    files.append(key['Key'])
        if len(files) == 0:
            raise Exception("No Files Found.")
        return files

    # Start with looking at files today, but try yesterday if that doesn't work (in case this runs close to midnight)
    today = datetime.today().strftime('%Y%m%d')
    yesterday = (datetime.today() - timedelta(1)).strftime('%Y%m%d')
    try:
        files = list_s3_files(bucket, get_s3_prefix(configuration, today))
    except Exception as e:
        print(f"Failed to get files for today ({e}). Trying again with yesterday's files")
        files = list_s3_files(bucket, get_s3_prefix(configuration, yesterday))

    # It seems this list is always sorted by default, but adding some sorting logic here may be necessary
    return files[-1:].pop()


def get_configuration(filename, previous_forecasts=0, return_input_files=True, mrf_timestep=1):
    """
        Parses the data file path to extract the file configuration, date, hour, reference time, and input files.

        Args:
            filename(dictionary): key (path) of a NWM channel file, or max_flows derived file.

        Returns:
            data_dict(dictionary): A dictionay containing the following possible values
                configuration(str): configuration of the run, i.e. medium_range_3day, analysis_assim, etc
                date(str): date of the forecast file (YYYYMMDD)
                hour(str): hour of the forecast file (HH)
                reference_time(str): the reference time associated with the input file
                input_files(list): All of the files needed to run analysis on the given configuration / reference time.
                model_type(str): Model run of the NWM. values are analysis_assim, short_range, or medium_range
                domain(str): Domain of the forecast. Values are conus, hawaii, or puertorico
                forecast_timestep(str): The timestamp of the forecast file, i.e. 018 for the f018 file
                mrf_timestep (int): The hour interval to use for mrf forecasts (default is 1, but old model is 3 hours)
    """
    input_files = []
    if 'max_flows' in filename:
        matches = re.findall(r"max_flows/(.*)/(\d{8})/\D*_(\d+day_)?(\d{2})_max_flows.*", filename)[0]
        date = matches[1]
        hour = matches[3]
        configuration = matches[0]
        reference_time = f"{date[:4]}-{date[-4:][:2]}-{date[-2:]} {hour[-2:]}:00:00"
        input_files.append(filename)

        days_match = re.findall(r"(\d+day)", filename)
        if days_match:
            configuration = f"{configuration}_{days_match[0]}"

        data_dict = {'date': date, 'hour': hour, 'configuration': configuration, 'reference_time': reference_time}
    elif 'max_stage' in filename:
        matches = re.findall(r"max_stage/(.*)/(\d{8})/(\d{2})_(\d{2})_ahps_forecasts.csv", filename)[0]
        date = matches[1]
        hour = matches[2]
        minute = matches[3]
        configuration = matches[0]
        reference_time = f"{date[:4]}-{date[-4:][:2]}-{date[-2:]} {hour[-2:]}:{minute[-2:]}:00"
        input_files.append(filename)

        metadata_file = filename.replace("ahps_forecasts", "ahps_metadata")
        input_files.append(metadata_file)

        data_dict = {
            'date': date, 'hour': hour, 'configuration': configuration,
            'reference_time': reference_time, 'input_files': input_files
        }
    else:
        if 'analysis_assim' in filename:
            matches = re.findall(r"(.*)/nwm.(\d{8})/(.*)/nwm.t(\d{2})z\.(.*)\..*\.tm(.*)\.(.*)\.nc", filename)[0]
        elif 'short_range' in filename or 'medium_range_mem1' in filename:
            matches = re.findall(r"(.*)/nwm.(\d{8})/(.*)/nwm.t(\d{2})z\.(.*)\..*\.f(\d{3,5}).(.*)\.nc", filename)[0]
        else:
            raise Exception(f"Configuration not set for {filename}")

        key_prefix = matches[0]
        date = matches[1]
        configuration = matches[2]
        hour = matches[3]
        model_type = matches[4]
        forecast_timestep = matches[5]
        domain = matches[6]
        reference_time = f"{date[:4]}-{date[-4:][:2]}-{date[-2:]} {hour[-2:]}:00:00"

        data_dict = {
            'date': date, 'hour': hour, 'configuration': configuration, 'reference_time': reference_time,
            'model_type': model_type, 'domain': domain, 'forecast_timestep': forecast_timestep
        }

        if return_input_files:
            input_files = get_input_files(key_prefix, reference_time, forecast_timestep, configuration, model_type,
                                          domain, previous_forecasts=previous_forecasts, mrf_timestep=mrf_timestep)
            data_dict['input_files'] = input_files

    return data_dict


def get_input_files(key_prefix, reference_time, forecast_timestep, configuration, model_type, domain,
                    previous_forecasts=0, mrf_timestep=1):
    """
        Using the file metadata, get a list of all the input files for the specified configuration.

        Args:
            key_prefix(str): AWS S3 key prefix for the forecast file. This prefix is static and the constant for all
                             files,
            reference_time(str): Reference time for the forecast ("2021-08-13 02:00:00"),
            forecast_timestep(str): The timestep of the forecast (i.e 072 for f072)
            configuration(str): The configuration for the forecast, i.e. short_range, short_range_hawaii,
                                analysis_assim_puertorico, etc,
            model_type(str): The model run for the forecast, i.e. short_range, medium_range, analysis_assim,
            domain(str): Domain of the forecast, i.e. conus, hawaii, puertorico,
            previous_forecasts(int): The number of previous forecast to retrieve. This is in addition to the forecast
                                     being ran. For example a previous_forecasts of 4 for analysis_assim will return 5
                                     total forecast (1 current, 4 previous)
            mrf_timestep (int): The hour interval to use for mrf forecasts (default is 1, but old model uses 3 hours)

        Returns:
            input_files(list): List of AWS keys for the specified forecast
    """
    input_files = []
    reference_date = datetime.strptime(reference_time, "%Y-%m-%d %H:%M:%S")

    if domain != 'conus' and "analysis_assim" not in configuration:
        forecast_length = 12  # hours
    elif model_type == 'medium_range':
        forecast_length = 6  # hours
    else:
        forecast_length = 1  # hours

    previous_hours = previous_forecasts * forecast_length  # compute hours between the desired forecasts

    # Loop through the desired forecasts
    for previous_hour in range(0, previous_hours+forecast_length, forecast_length):
        previous_date_time = reference_date - timedelta(hours=previous_hour)
        previous_date = previous_date_time.strftime("%Y%m%d")
        previous_hour = previous_date_time.strftime("%H")
        base_file = f"{key_prefix}/nwm.{previous_date}/{configuration}/nwm.t{previous_hour}z.{model_type}.channel_rt"

        if configuration in ['analysis_assim', 'analysis_assim_puertorico']:
            input_files.append(f"{base_file}.tm00.{domain}.nc")
        elif configuration == 'analysis_assim_hawaii':
            input_files.append(f"{base_file}.tm0000.{domain}.nc")
        else:
            if configuration == 'short_range_hawaii':
                leads = []
                for lead1 in range(0, 4800, 100):
                    for lead2 in [0, 15, 30, 45]:
                        lead = lead1+lead2
                        leads.append(f"{lead:05}")
                leads.pop(0)
                leads.append(f"{4800:05}")
            elif configuration == 'short_range':
                leads = [f"{lead:03}" for lead in range(1, 19)]
            elif configuration == 'short_range_puertorico':
                leads = [f"{lead:03}" for lead in range(1, 49)]
            elif configuration == 'medium_range_mem1':
                if mrf_timestep == 3:
                    base_file = f"{base_file}_1"
                    leads = [f"{lead:03}" for lead in range(3, int(forecast_timestep)+1, 3)]
                else:
                    base_file = f"{base_file}_1"
                    leads = [f"{lead:03}" for lead in range(1, int(forecast_timestep)+1)]
            else:
                raise Exception(f"function not configured for {configuration}")

            for lead in leads:
                input_files.append(f"{base_file}.f{lead}.{domain}.nc")

    return sorted(input_files)


def get_db_credentials(db_type):
    """
    This function pulls database credentials from environment variables.
    It first checks for a password in an environment variable.
    If that doesn't exist, it tries looking or a secret name to query for
    the password using the get_secret_password function.

    Returns:
        db_host (str): The host address of the PostgreSQL database.
        db_name (str): The target database name.
        db_user (str): The database user with write access to authenticate with.
        db_password (str): The password for the db_user.

    """
    db_type = db_type.upper()

    db_host = os.environ[f'{db_type}_DB_HOST']
    db_name = os.environ[f'{db_type}_DB_DATABASE']
    db_user = os.environ[f'{db_type}_DB_USERNAME']
    aws_region = os.environ['AWS_REGION']
    try:
        db_password = os.getenv(f'{db_type}_DB_PASSWORD')
    except Exception:
        try:
            db_password = get_secret_password(os.getenv(f'{db_type}_RDS_SECRET_NAME'), aws_region, 'password')
        except Exception as e:
            print(f"Couldn't get db password from environment variable or secret name. ({e})")

    return db_host, db_name, db_user, db_password


def get_db_engine(db_type):
    from sqlalchemy import create_engine

    print("Creating the viz DB engine")
    db_host, db_name, db_user, db_password = get_db_credentials(db_type)
    db_engine = create_engine(f'postgresql://{db_user}:{db_password}@{db_host}/{db_name}')

    return db_engine


def get_db_connection(db_type, asynchronous=False):
    import psycopg2

    print("Creating the viz DB engine")
    db_host, db_name, db_user, db_password = get_db_credentials(db_type)
    connection = psycopg2.connect(
        f"host={db_host} dbname={db_name} user={db_user} password={db_password}", async_=asynchronous
    )

    return connection


def get_db_values(table, columns, db_type="viz"):
    import pandas as pd

    print("Connecting to DB")
    db_engine = get_db_engine(db_type)

    if not type(columns) == list:
        raise Exception("columns argument must be a list of column names")

    columns = ",".join(columns)
    print(f"Retrieving values for {columns}")
    df = pd.read_sql(f'SELECT {columns} FROM {table}', db_engine)

    return df


def get_service_metadata(include_ingest_sources=True, include_latest_ref_time=False):
    """
    This function pulls service metadata from the admin.services database table.

    Returns:
        results (dictionary): A python dictionary containing the database table data.
    """
    import psycopg2.extras

    if include_ingest_sources is True:
        extra_sql = " join admin.services_ingest_sources ON admin.services.service = admin.services_ingest_sources.service"
    else:
        extra_sql = ""

    if include_latest_ref_time is True:
        extra_sql += """ LEFT OUTER JOIN (SELECT service as service2, to_char(min(reference_time)::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') as reference_time
                        FROM admin.services_ingest_sources a JOIN
			            (SELECT target, max(reference_time) as reference_time FROM admin.ingest_status where status='Import Complete' group by target) b
		                ON a.ingest_table = b.target group by service) AS ref_times
                        on admin.services.service = ref_times.service2"""
    
    connection = get_db_connection("viz")
    with connection.cursor(cursor_factory=psycopg2.extras.DictCursor) as cur:
        cur.execute(f"SELECT * FROM admin.services{extra_sql};")
        column_names = [desc[0] for desc in cur.description]
        response = cur.fetchall()
        cur.close()
    connection.close()
    return list(map(lambda x: dict(zip(column_names, x)), response))


def load_df_into_db(table_name, db_engine, df):
    import pandas as pd

    schema = table_name.split(".")[0]
    table = table_name.split(".")[-1]

    print(f"Dropping {table_name} if it exists")
    db_engine.execute(f'DROP TABLE IF EXISTS {table_name};')  # Drop the stage table if it exists

    print("Getting sql to create table")
    create_table_statement = pd.io.sql.get_schema(df, table_name)
    replace_values = {'"geom" TEXT': '"geom" GEOMETRY', "REAL": "DOUBLE PRECISION"}  # Correct data types
    for a, b in replace_values.items():
        create_table_statement = create_table_statement.replace(a, b)

    create_table_statement = create_table_statement.replace(f'"{table_name}"', table_name)

    print(f"Creating {table_name}")
    db_engine.execute(create_table_statement)  # Create the new empty stage table

    print(f"Adding data to {table_name}")
    df.to_sql(con=db_engine, schema=schema, name=table, index=False, if_exists='append')


def run_sql_file_in_db(db_type, sql_file):
    print("Getting connection to run sql files")
    sql = open(sql_file, 'r').read()
    db_connection = get_db_connection(db_type)

    try:
        cur = db_connection.cursor()
        print(f"Running {sql_file}")
        cur.execute(sql)
        db_connection.commit()
    except Exception as e:
        raise e
    finally:
        db_connection.close()


def move_data_to_another_db(origin_db, dest_db, origin_table, dest_table, stage=True, add_oid=True,
                            add_geom_index=True):
    import pandas as pd

    origin_engine = get_db_engine(origin_db)
    dest_engine = get_db_engine(dest_db)

    if stage:
        dest_final_table = dest_table
        dest_final_table_name = dest_final_table.split(".")[1]

        dest_table = f"{dest_table}_stage"

    print(f"Reading {origin_table} from the {origin_db} db")
    df = pd.read_sql(f'SELECT * FROM {origin_table}', origin_engine)  # Read from the newly created table

    print(f"Loading {origin_table} into {dest_table}  in the {dest_db} db")
    load_df_into_db(dest_table, dest_engine, df)

    if add_oid:
        print(f"Adding an OID to the {dest_table}")
        dest_engine.execute(f'ALTER TABLE {dest_table} ADD COLUMN OID SERIAL PRIMARY KEY;')

    if add_geom_index:
        print(f"Adding an spatial index to the {dest_table}")
        dest_engine.execute(f'CREATE INDEX ON {dest_table} USING GIST (geom);')  # Add a spatial index

    if stage:
        print(f"Renaming {dest_table} to {dest_final_table}")
        dest_engine.execute(f'DROP TABLE IF EXISTS {dest_final_table};')  # Drop the published table if it exists
        dest_engine.execute(f'ALTER TABLE {dest_table} RENAME TO {dest_final_table_name};')  # Rename the staged table

def check_if_file_exists(bucket, file, download=False, download_subfolder=None):
    import requests
    from viz_classes import s3_file
    import xarray as xr
    import tempfile
    
    s3 = boto3.client('s3')
    file_exists = False

    tempdir = tempfile.mkdtemp()
    if download_subfolder:
        download_folder=os.path.join(tempdir, download_subfolder)
        if not os.path.exists(download_folder):
            os.mkdir(download_folder)
        download_path = os.path.join(download_folder, os.path.basename(file))
    else:
        download_path = os.path.join(tempdir, os.path.basename(file))
    https_file = None

    if "https" in file:
        https_file = file
        if requests.head(file).status_code == 200:
            file_exists = True
            print(f"{file} exists.")
        else:
            raise Exception(f"https file doesn't seem to exist: {file}")   
    else:
        if s3_file(bucket, file).check_existence():
            file_exists = True
            print(f"{file} exists in {bucket}")
        else:
            if "/prod" in file:

                date_metadata = re.findall("(\d{8})/[a-z0-9_]*/nwm.t(\d{2})z.*[ftm](\d*)\.", file)
                date = date_metadata[0][0]
                initialize_hour = date_metadata[0][1]
                delta_hour = date_metadata[0][2]

                model_initialization_datetime = datetime.strptime(f"{date}{initialize_hour}", "%Y%m%d%H")
                forecast_datetime = model_initialization_datetime + timedelta(hours=int(delta_hour))
                forecast_date = forecast_datetime.strftime("%Y")
                forecast_date_hour = forecast_datetime.strftime("%Y%m%d%H")
                
                google_file = file.replace('common/data/model/com/nwm/prod', 'https://storage.googleapis.com/national-water-model')
                if "channel" in file:
                    retro_file = f"https://noaa-nwm-retrospective-2-1-pds.s3.amazonaws.com/model_output/{forecast_date}/{forecast_date_hour}00.CHRTOUT_DOMAIN1.comp"
                else:
                    retro_file = f"https://noaa-nwm-retrospective-2-1-pds.s3.amazonaws.com/forcing/{forecast_date}/{forecast_date_hour}00.LDASIN_DOMAIN1.comp"
                    
                if requests.head(google_file).status_code == 200:
                    file_exists = True
                    https_file = google_file
                    print("File does not exist on S3 (even though it should), but does exists on Google Cloud.")
                elif requests.head(retro_file).status_code == 200:
                    file_exists = True
                    https_file = retro_file
                    print("File does not exist on S3 (even though it should), but does exists in the retrospective data in AWS.")

        if not file_exists:
            raise MissingS3FileException(f"{file} does not exist on S3.")

    
    if download:
        if https_file:
            print(f"Downloading {https_file}")
            tries = 0
            while tries < 3:
                open(download_path, 'wb').write(requests.get(https_file, allow_redirects=True).content)
                
                try:
                    xr.open_dataset(download_path)
                    tries = 3
                except:
                    print(f"Failed to open {download_path}. Retrying in case file was corrupted on download")
                    tries +=1
        else:
            print(f"Downloading {file} from s3")
            s3.download_file(bucket, file, download_path)
        
        return download_path
    
    return file
    
def parse_range_token_value(reference_date_file, range_token, existing_list = []):
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
    if existing_list == []:
        existing_list = [reference_date_file]
    
    for item in existing_list:
        for i in range(range_min, range_max, range_step):
            range_value = number_format % i
            new_input_file = item.replace(f"{{{{range:{range_token}}}}}", range_value)
            new_input_files.append(new_input_file)

    return new_input_files


def get_file_tokens(file_pattern):
    token_dict = {}
    tokens = re.findall("{{[a-z]*:[^{]*}}", file_pattern)
    token_dict = {'datetime': [], 'range': [], 'variable': []}
    for token in tokens:
        token_key = token.split(":")[0][2:]
        token_value = token.split(":")[1][:-2]

        token_dict[token_key].append(token_value)
        
    return token_dict

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

def parse_variable_token_value(input_file, variable_token):
    
    variable_value = os.environ[variable_token]
    new_input_file = input_file.replace(f"{{{{variable:{variable_token}}}}}", variable_value)

    return new_input_file

def get_formatted_files(file_pattern, token_dict, reference_date):
    reference_date_file = file_pattern
    reference_date_files = []
    for variable_token in token_dict['variable']:
        reference_date_file = parse_variable_token_value(reference_date_file, variable_token)
        
    for datetime_token in token_dict['datetime']:
        reference_date_file = parse_datetime_token_value(reference_date_file, reference_date, datetime_token)

    if token_dict['range']:
        unique_range_tokens = list(set(token_dict['range']))
        for range_token in unique_range_tokens:
            reference_date_files = parse_range_token_value(reference_date_file, range_token, existing_list=reference_date_files)
    else:
        reference_date_files = [reference_date_file]
        
    return reference_date_files

def generate_file_list(file_pattern, file_step, file_window, reference_time):
    import pandas as pd
    import isodate
    
    file_list = [] 
    if 'common/data/model/com/nwm/prod' in file_pattern and (datetime.today() - timedelta(29)) > reference_time:
        file_pattern = file_pattern.replace('common/data/model/com/nwm/prod', 'https://storage.googleapis.com/national-water-model')

    if file_window:
        if not file_step:
            file_step = None
        reference_dates = pd.date_range(reference_time-isodate.parse_duration(file_window), reference_time, freq=file_step)
    else:
        reference_dates = [reference_time]

    token_dict = get_file_tokens(file_pattern)

    for reference_date in reference_dates:
        reference_date_files = get_formatted_files(file_pattern, token_dict, reference_date)
        file_list.extend(reference_date_files)
        
    return file_list

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
