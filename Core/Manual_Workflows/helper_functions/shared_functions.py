from ipywidgets import Checkbox
import json
import os
from IPython.display import display, HTML
import boto3
import botocore
from sqlalchemy import create_engine, text
import psycopg2
import psycopg2.extras
import pandas as pd
from matplotlib import pyplot as plt
from matplotlib.colors import LinearSegmentedColormap
from sqlalchemy.exc import ResourceClosedError
from botocore.exceptions import ClientError
import base64
import re
import time
import matplotlib as mpl
from datetime import timedelta
import sqlalchemy

pd.options.mode.chained_assignment = None

display(HTML("<style>.container { width:90% !important; }</style>"))

# Oct 16, 2024 - moved hots/db names user names and passwords to AWS_Secret_keys folder. 
# this needs to be test

def load_checklist(service_name):
    display(HTML("<style>.container { width:90% !important; } .widget-checkbox { width:auto !important; } .widget-label { width:0 !important; }</style>"))

    service_json = f'service_jsons/{service_name}.json'

    # If service json does not exist, then create a new json file with default checkboxes and values
    if not os.path.exists(service_json):
        print(f"Creating {service_json} for new {service_name} service ")
        data = {
            "update_service_metadata": False,
            "load_datasets": False,
            "create_sql": False,
            "check_sql": False,
            "save_sql_table": False,
            "create_pro_project": False,
            "setup_code_review": False,
            "finished_code_review": False,
            "implement_code_review_changes": False,
            "add_sql_to_repo": False,
            "add_pro_project_to_repo": False,
            "add_notebook_to_repo": False,
            "ti_implement": False
        }

        with open(service_json, 'w') as f:
            json.dump(data, f)

    with open(service_json, 'r') as f:
        data = json.load(f)

    update_service_metadata = Checkbox(value=data["update_service_metadata"], description_tooltip="update_service_metadata", description="Update service metadata in first notebook cell")
    load_datasets = Checkbox(value=data["load_datasets"], description_tooltip="load_datasets", description="Have Corey or Tyler add any new dependent datasets to the DB")
    create_sql = Checkbox(value=data["create_sql"], description_tooltip="create_sql", description="Create SQL for service data")
    check_sql = Checkbox(value=data["check_sql"], description_tooltip="check_sql", description="Check SQL output for accuracy")
    save_sql_table = Checkbox(value=data["save_sql_table"], description_tooltip="save_sql_table", description="Update SQL to save a table in the dev schema")
    create_pro_project = Checkbox(value=data["create_pro_project"], description_tooltip="create_pro_project", description="Create a pro project for the new service")
    setup_code_review = Checkbox(value=data["setup_code_review"], description_tooltip="setup_code_review", description="Setup a code review meeting with the team to go over the service")
    finished_code_review = Checkbox(value=data["finished_code_review"], description_tooltip="finished_code_review", description="Complete code review")
    implement_code_review_changes = Checkbox(value=data["implement_code_review_changes"], description_tooltip="implement_code_review_changes", description="Implement any service changes from the code review")
    add_sql_to_repo = Checkbox(value=data["add_sql_to_repo"], description_tooltip="add_sql_to_repo", description="Admin Task - Add SQL to repo (Adding INTO statements)")
    add_pro_project_to_repo = Checkbox(value=data["add_pro_project_to_repo"], description_tooltip="add_pro_project_to_repo", description="Admin Task - Add pro poject to repo (Updating to use Query Layer)")
    add_notebook_to_repo = Checkbox(value=data["add_notebook_to_repo"], description_tooltip="add_notebook_to_repo", description="Add notebook to repo")
    ti_implement = Checkbox(value=data["ti_implement"], description_tooltip="ti_implement", description="Admin Task - Implement service into the TI environment")

    def on_value_change(change):
        key = change['owner'].description_tooltip
        value = change['new']

        data[key] = value
        with open(service_json, 'w') as f:
            json.dump(data, f)

    update_service_metadata.observe(on_value_change, names='value')
    load_datasets.observe(on_value_change, names='value')
    create_sql.observe(on_value_change, names='value')
    check_sql.observe(on_value_change, names='value')
    save_sql_table.observe(on_value_change, names='value')
    create_pro_project.observe(on_value_change, names='value')
    setup_code_review.observe(on_value_change, names='value')
    finished_code_review.observe(on_value_change, names='value')
    implement_code_review_changes.observe(on_value_change, names='value')
    add_sql_to_repo.observe(on_value_change, names='value')
    add_pro_project_to_repo.observe(on_value_change, names='value')
    add_notebook_to_repo.observe(on_value_change, names='value')
    ti_implement.observe(on_value_change, names='value')

    display(update_service_metadata)
    display(load_datasets)
    display(create_sql)
    display(check_sql)
    display(save_sql_table)
    display(create_pro_project)
    display(setup_code_review)
    display(finished_code_review)
    display(implement_code_review_changes)
    display(add_notebook_to_repo)
    display(add_sql_to_repo)
    display(add_pro_project_to_repo)
    display(ti_implement)

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
    try:
        db_password = os.getenv(f'{db_type}_DB_PASSWORD')
    except Exception:
        try:
            db_password = get_secret_password(os.getenv(f'{db_type}_RDS_SECRET_NAME'), 'us-east-1', 'password')
        except Exception as e:
            print(f"Couldn't get db password from environment variable or secret name. ({e})")

    return db_host, db_name, db_user, db_password

def get_db_connection_url(db_type):
    db_host, db_name, db_user, db_password = get_db_credentials(db_type)
    return f'postgresql://{db_user}:{db_password}@{db_host}/{db_name}'

def get_db_engine(db_type):
    db_host, db_name, db_user, db_password = get_db_credentials(db_type)
    db_engine = create_engine(f'postgresql://{db_user}:{db_password}@{db_host}/{db_name}')

    return db_engine


def get_db_connection(db_type, asynchronous=False):
    db_host, db_name, db_user, db_password = get_db_credentials(db_type)
    connection = psycopg2.connect(
        f"host={db_host} dbname={db_name} user={db_user} password={db_password}", async_=asynchronous
    )

    return connection


# Aug 18, 2024, updated to add "where" clause
def get_db_values(table, columns, db_type="viz", where=""):
    db_engine = get_db_engine(db_type)

    if not type(columns) == list:
        raise Exception("columns argument must be a list of column names")

    columns = ",".join(columns)
    print(f"Retrieving values for {columns}")
    sql = f"SELECT {columns} FROM {table}"
    if where != "":
        sql = f"{sql} WHERE {where}"
    df = pd.read_sql(sql, db_engine)

    return df


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
        
        
def sql_to_dataframe(sql, db_type="viz", as_geo=False):
    if sql.endswith(".sql"):
        sql = open(sql, 'r').read()

    db_engine = get_db_engine(db_type)
    if not as_geo:
        import pandas as pd
        df = pd.read_sql(sql, db_engine)
    else:
        import geopandas as gdp
        df = gdp.GeoDataFrame.from_postgis(sql, db_engine)

    db_engine.dispose()
    return df


def execute_sql(sql, db_type="viz"):
    db_connection = get_db_connection(db_type)

    try:
        cur = db_connection.cursor()
        cur.execute(sql)
        db_connection.commit()
    except Exception as e:
        raise e
    finally:
        db_connection.close()

def run_sql_in_db(sql, db_type="viz", return_geodataframe=False):
    connection = get_db_engine(db_type)

    try:
        if not return_geodataframe:
            df = pd.read_sql(sql, connection)
        else:
            import geopandas as gdp
            df = gdp.GeoDataFrame.from_postgis(sql, connection)
    except ResourceClosedError as e:
        print(e)
        # Nothing return because sql created/update tables
        return
    
    return df

def get_schemas(db_type="viz"):
    sql = "SELECT DISTINCT(table_schema) FROM information_schema.tables ORDER BY table_schema;"
    return run_sql_in_db(sql, db_type=db_type)


def get_tables(schema, containing='', db_type="viz"):
    sql = f"SELECT table_name FROM information_schema.tables WHERE table_schema = '{schema}'"
    if containing:
        sql += f" AND table_name LIKE '%%{containing}%%'"
    sql += " ORDER BY table_name;"
    
    return run_sql_in_db(sql, db_type=db_type)

def get_columns(schema_and_optional_table, table='', db_type="viz"):
    if '.' in schema_and_optional_table and not table:
        schema, table = schema_and_optional_table.split('.')
    else:
        schema = schema_and_optional_table
    sql = f"""
        SELECT column_name, data_type
        FROM information_schema.columns
        WHERE table_schema = '{schema}' AND table_name = '{table}';
    """
    
    return run_sql_in_db(sql, db_type=db_type)

def map_column(gdf, column, colormap=None, title=None, basemap=True, categorical=False, legend=True, show_plot=True):
    
    legend_kwds=None
    if categorical:
        legend_kwds={'shrink': 0.42, 'label': column}

    if not colormap:
        cmap = "Blues"
    elif type(colormap) is dict:
        cmap = LinearSegmentedColormap.from_list("custom_cmap", list(colormap.values()), N=len(colormap))
        if categorical:
            legend_kwds={}
            gdf[column] = gdf[column].astype(pd.api.types.CategoricalDtype(categories=colormap.keys()))
    else:
        cmap = colormap
    
    if not show_plot:
        plt.ioff()
    ax = gdf.plot(figsize=(20,20), column=column, legend=legend, cmap=cmap, legend_kwds=legend_kwds)
        
    ax.set_axis_off()
    ax.set_title(title)

    if basemap:
        import contextily as cx
        cx.add_basemap(ax, source=cx.providers.Stamen.TonerLite)
        
    return ax

def sql_to_leafmap(db_alias, sql, layer_name="My Layer", fill_colors=["red", "green", "blue"]):
    import leafmap

    db_host, db_name, db_user, db_password = get_db_credentials(db_alias)
    con = leafmap.connect_postgis(
        database=db_name, host=db_host, user=db_user, password=db_password
    )
    m = leafmap.Map()
    m.add_gdf_from_postgis(
        sql, con, layer_name=layer_name, fill_colors=fill_colors
    )
    return m

# TODO: Aug 2024: Consider moving this to the new s3_shared_functions file  (or more like just the s3 code in this function)
def save_gdf_shapefile(gdf, output_folder, shapefile_name):
    shapefiles_folder = folder

    gdf.to_file(f'{shapefiles_folder}/{shapefile_name}.shp', index=False)

    for file in os.listdir(shapefiles_folder):
        file_basename = os.path.basename(file).split(".")[0]
        if file_basename == shapefile_name:
            file_path = os.path.join(shapefiles_folder, file)
            s3_key = f"{bucket_folder}/{file}"

            print(f"Uploading {file} to {upload_bucket}:/{s3_key}")
            s3_client.upload_file(
               file_path, upload_bucket, s3_key, ExtraArgs={"ServerSideEncryption": "aws:kms"}
            )

            
# TODO: Aug 2024: Consider moving this to the new s3_shared_functions file  (or more like just the s3 code in this function)
def save_gdf_shapefile_to_s3(gdf, shapefile_name):
    s3_client = boto3.client('s3')
    shapefiles_folder = "shapefiles"
    upload_bucket = "hydrovis-dev-fim-us-east-1"
    bucket_folder = "sagemaker/shapefiles"

    gdf.to_file(f'{shapefiles_folder}/{shapefile_name}.shp', index=False)

    for file in os.listdir(shapefiles_folder):
        file_basename = os.path.basename(file).split(".")[0]
        if file_basename == shapefile_name:
            file_path = os.path.join(shapefiles_folder, file)
            s3_key = f"{bucket_folder}/{file}"

            print(f"Uploading {file} to {upload_bucket}:/{s3_key}")
            s3_client.upload_file(
               file_path, upload_bucket, s3_key, ExtraArgs={"ServerSideEncryption": "aws:kms"}
            )

            
            
def load_df_into_db(table_name, db_engine, df, dtype={'oid': sqlalchemy.types.Integer()}, epsg=None, drop_first=True, bigint_fields=[]):
    schema = table_name.split(".")[0]
    table = table_name.split(".")[-1]

    # Drop the old table if it exists and recreate it
    if drop_first:
        connection = database("egis").get_db_connection()
        with connection.cursor(cursor_factory=psycopg2.extras.DictCursor) as cur:
            print(f"Dropping {table_name} if it exists")
            conn.execute(text(f'DROP TABLE IF EXISTS {table_name};'))  # Drop the stage table if it exists

            print("Getting sql to create table")
            create_table_statement = pd.io.sql.get_schema(df, table_name)
            replace_values = {
                '"geom" TEXT': '"geom" GEOMETRY', "REAL": "DOUBLE PRECISION", '"coastal" INTEGER': '"coastal" BOOLEAN'
            }  # Correct data types
            for a, b in replace_values.items():
                create_table_statement = create_table_statement.replace(a, b)

            create_table_statement = create_table_statement.replace(f'"{table_name}"', table_name)

            if epsg:
                create_table_statement = create_table_statement.replace(f'"geom" GEOMETRY', f'"geom" GEOMETRY(Geometry,{epsg})')

            if bigint_fields:
                for field in bigint_fields:
                    create_table_statement = create_table_statement.replace(f'"{field}" INTEGER', f'"{field}" BIGINT')
            print(create_table_statement)

            print(f"Creating {table_name}")
            conn.execute(text(create_table_statement))  # Create the new empty stage table
    
    print(f"Adding data to {table_name}")
    df.to_sql(con=db_engine, schema=schema, name=table, index=False, if_exists='append', chunksize=200000)
    
def move_data_to_another_db(origin_db, dest_db, origin_table, dest_table, stage=True, add_oid=True,
                            add_geom_index=True, columns="*"):
    origin_engine = get_db_engine(origin_db)
    dest_engine = get_db_engine(dest_db)

    if stage:
        dest_final_table = dest_table
        dest_final_table_name = dest_final_table.split(".")[1]

        dest_table = f"{dest_table}_stage"

    print(f"Reading {origin_table} from the {origin_db} db")
    df = get_db_values(origin_table, columns, db_type=origin_db)

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
        
def get_service_metadata(run_only=True):
    from helper_functions.viz_classes import database
    """
    This function pulls service metadata from the admin.services database table.

    Returns:
        results (dictionary): A python dictionary containing the database table data.
    """
    import psycopg2.extras
    service_filter = run_filter = ""
    if run_only:
        run_filter = " WHERE run is True"
    connection = database("viz").get_db_connection()
    with connection.cursor(cursor_factory=psycopg2.extras.DictCursor) as cur:
        cur.execute(f"SELECT * FROM admin.services_new {run_filter};")
        column_names = [desc[0] for desc in cur.description]
        response = cur.fetchall()
        cur.close()
    connection.close()
    return list(map(lambda x: dict(zip(column_names, x)), response))

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
    elif "pcpanl" in filename:
        matches = re.findall(r"(.*)/pcpanl.(\d{8})/st4_(.*).(\d{10})\.01h.grb2", filename)[0]
        key_prefix = matches[0]
        domain = matches[2]
        date = matches[3][:-2]
        hour = matches[3][-2:]
        reference_time = f"{date[:4]}-{date[-4:][:2]}-{date[-2:]} {date[-2:]}:00:00"
        model_type = "pcpanl"
        model_output = "pcpanl"

        data_dict = {
            'date': date, 'hour': hour, 'domain': domain, 'configuration': model_type,
            'reference_time': reference_time, 'model_type': model_type, "model_output": model_output
        }
        
    else:
        if 'analysis_assim' in filename:
            matches = re.findall(r"(.*)/nwm.(\d{8})/(.*)/nwm.t(\d{2})z\.(.*)\.(.*)\.tm(.*)\.(.*)\.nc", filename)[0]
        elif 'short_range' in filename or 'medium_range_mem1' in filename:
            matches = re.findall(r"(.*)/nwm.(\d{8})/(.*)/nwm.t(\d{2})z\.(.*)\.(.*)\.f(\d{3,5}).(.*)\.nc", filename)[0]
        else:
            raise Exception(f"Configuration not set for {filename}")

        key_prefix = matches[0]
        date = matches[1]
        configuration = matches[2]
        hour = matches[3]
        model_type = matches[4]
        model_output = matches[5]
        forecast_timestep = matches[6]
        domain = matches[7]
        reference_time = f"{date[:4]}-{date[-4:][:2]}-{date[-2:]} {hour[-2:]}:00:00"

        data_dict = {
            'date': date, 'hour': hour, 'configuration': configuration, 'reference_time': reference_time,
            'model_type': model_type, 'domain': domain, 'forecast_timestep': forecast_timestep, "model_output": model_output
        }

        if return_input_files:
            input_files = get_input_files(key_prefix, reference_time, forecast_timestep, configuration, model_type,
                                          domain, previous_forecasts=previous_forecasts, mrf_timestep=mrf_timestep)
            data_dict['input_files'] = input_files

    return data_dict

# Function to get a daterange list from a start and end date.
def daterange(start_date, end_date):
    for n in range(int((end_date - start_date).days + 1)):
        yield start_date + timedelta(n)

# Function to kick off past_event pipelines for a specified date & time range
def run_pipelines(start_date, end_date, reference_hours, configurations, initialize_pipeline_arn, states_to_run_fim = None, skip_fim = False, interval_minutes=20):
    lambda_config = botocore.client.Config(max_pool_connections=1, connect_timeout=60, read_timeout=600)
    lambda_client = boto3.client('lambda', config=lambda_config)
    for configuration in configurations:
        for key, value in configuration.items():
            configuration_name = key
            bucket = value
        for day in daterange(start_date, end_date):
            reference_date = day.strftime("%Y-%m-%d")
            for reference_hour in reference_hours:
                dump_dict = {"configuration": configuration_name,
                             "bucket": bucket,
                             "reference_time": f"{reference_date} {reference_hour}",
                             "states_to_run_fim": states_to_run_fim,
                             "skip_fim": skip_fim}
                lambda_client.invoke(FunctionName=initialize_pipeline_arn, InvocationType='Event', Payload=json.dumps(dump_dict))
                print(f"Invoked viz_initialize_pipeline function with payload: {dump_dict}.")
                time.sleep(interval_minutes*60)

def update_service_metadata(service, configuration, summary, description, tags, credits, egis_server, egis_folder, max_flows_sql_name=None, service_sql_name=None, summary_sql_name=None, fim_service=False, feature_service=False, run=False, fim_configs=None, public_service=False, max_flow_method="db"):
        
    if not fim_configs:
        fim_configs = []
        
    if not summary_sql_name:
        summary_sql_name = []
        
    if not max_flows_sql_name:
        max_flows_sql_name = []
    
    sql = f"""
    DELETE FROM admin.services WHERE service = '{service}';
    """
    run_sql_in_db(sql, db_type="viz")

    sql = f"""
    INSERT INTO admin.services(
    service, configuration, postprocess_max_flows, postprocess_service, postprocess_summary, summary, description, tags, credits, egis_server, egis_folder, fim_service, feature_service, run, fim_configs, public_service, max_flow_method)
    VALUES ('{service}', '{configuration}', array{str(max_flows_sql_name).lower()}::text[], '{service_sql_name}', array{str(summary_sql_name).lower()}::json[], '{summary}', '{description}', '{tags}', '{credits}', '{egis_server}', '{egis_folder}', {str(fim_service).lower()}, {str(feature_service).lower()}, {str(run).lower()}, array{str(fim_configs).lower()}::text[], {str(public_service).lower()}, '{max_flow_method}')
    """
    
    sql = sql.replace("'None'", "null")
    
    run_sql_in_db(sql, db_type="viz")
    
def update_service_data_flows(service, flow_id, step, source_table, target_table, target_keys, file_format=None, file_step=None, file_window=None):
    
    if step not in ['ingest', 'fim_prep', 'max_flows']:
        raise Exception("step must be one of ingest, fim_prep, or max_flows")

    if target_keys:
        if isinstance(target_keys, str) and "(" in target_keys:
            pass
        else:
            if not isinstance(target_keys, list):
                target_keys = [target_keys]

            target_keys = f"({','.join(target_keys)})"
    
    sql = f"""
    DELETE FROM admin.pipeline_data_flows WHERE service = '{service}' AND flow_id = '{flow_id}';
    """
    run_sql_in_db(sql, db_type="viz")

    sql = f"""
    INSERT INTO admin.pipeline_data_flows(
        service, flow_id, step, file_format, source_table, target_table, target_keys, file_step, file_window)
    VALUES ('{service}', '{flow_id}', '{step}', '{file_format}', '{source_table}', '{target_table}', '{target_keys}', '{file_step}', '{file_window}');
    """
    sql = sql.replace("'None'", "null")
    
    run_sql_in_db(sql, db_type="viz")
    
def clear_db_connections(user="viz_proc_dev_rw_user"):
    sql = f"""
        SELECT pg_terminate_backend(pg_stat_activity.pid)
        FROM pg_stat_activity
        WHERE pg_stat_activity.datname = 'vizprocessing'
        AND pid <> pg_backend_pid();
    """
    
    run_sql_in_db(sql, db_type="viz")

def show_colors(colors):
    """
    Draw a square for each color contained in the colors list
    given in argument.
    """
    with plt.rc_context(plt.rcParamsDefault):
        fig = plt.figure(figsize=(6, 1), frameon=False)
        ax = fig.add_subplot(111)
        for x, color in enumerate(colors):
            ax.add_patch(
                mpl.patches.Rectangle(
                    (x, 0), 1, 1, facecolor=color
                )
            )
        ax.set_xlim((0, len(colors)))
        ax.set_ylim((0, 1))
        ax.set_xticks([])
        ax.set_yticks([])
        ax.set_aspect("equal")
    
    return fig

def show_symbology(symbology_list):
    """
        Args:
            - symbology_list(list): list containing a list of color, upper bound scale, and label
    """
    color_scale = []
    bound_scale = []
    labels = []
    for class_break in symbology_list:
        color = '#%02x%02x%02x' % tuple(class_break[0][:3]) if type(class_break[0]) is list else class_break[0]
        color_scale.append(color)
        bound_scale.append(class_break[1])
        labels.append(class_break[2])

    print(bound_scale)
    print(labels)
    display(show_colors(color_scale))
    
def open_raster(bucket, file, variable):
    download_path = check_if_file_exists(bucket, file, download=True)
    print(f"--> Downloaded {file} to {download_path}")
    
    print(f"Opening {variable} in raster for {file}")
    import rioxarray as rxr
    ds = rxr.open_rasterio(download_path, variable=variable)
    
    # for some files like NBM alaska, the line above opens the attribute itself
    try:
        data = ds[variable]
    except:
        data = ds

    if "alaska" in file:
        proj4 = "+proj=stere +lat_0=90 +lat_ts=60 +lon_0=-135 +x_0=0 +y_0=0 +R=6370000 +units=m +no_defs"
    else:
        try:
            proj4 = data.proj4
        except:
            proj4 = ds.proj4

    from rasterio.crs import CRS
    crs = CRS.from_proj4(proj4)

    os.remove(download_path)
    
    return [data, crs]

def create_raster(data, crs, raster_name):
    print(f"Creating raster for {raster_name}")
    data.rio.write_crs(crs, inplace=True)
    data.rio.write_nodata(0, inplace=True)
    
    if "grid_mapping" in data.attrs:
        data.attrs.pop("grid_mapping")
        
    if "_FillValue" in data.attrs:
        data.attrs.pop("_FillValue")

    local_raster = f'/tmp/{raster_name}.tif'

    print(f"Saving raster to {local_raster}")
    data.rio.to_raster(local_raster)
    
    return local_raster


# TODO: Aug 2024: Move this to new s3_shared_functions
def upload_raster(local_raster, output_bucket, output_workspace):
    raster_name = os.path.basename(local_raster)
    
    s3_raster_key = f"{output_workspace}/tif/{raster_name}"
    
    print(f"--> Uploading raster to s3://{output_bucket}/{s3_raster_key}")
    s3 = boto3.client('s3')
    
    s3.upload_file(local_raster, output_bucket, s3_raster_key)
    os.remove(local_raster)

    return s3_raster_key




def sum_rasters(bucket, input_files, variable):
    print(f"Adding {variable} variable of {len(input_files)} raster(s)...")
    sum_initiated = False
    for input_file in input_files:
        print(f"Adding {input_file}...")
        data, crs = open_raster(bucket, input_file, variable)
        time_index = 0
        if len(data.time) > 1:
            time_index = -1
            for i, t in enumerate(data.time):
                if str(float(data.sel(time=t)[0][0])) != 'nan':
                    time_index = i
                    break
            if (time_index < 0):
                raise Exception(f"No valid time steps were found in file: {input_file}")
        
        if not sum_initiated:
            data_sum = data.sel(time=data.time[time_index])
            sum_initiated = True
        else:
            data_sum += data.sel(time=data.time[time_index])
    print("Done adding rasters!")
    return data_sum, crs


def move_data_from_viz_to_egis(viz_schema_and_table, egis_schema_and_table):
    egis_connection = get_db_connection('egis')
    
    viz_schema, viz_table = viz_schema_and_table.split('.')
    
    with egis_connection:
        with egis_connection.cursor() as cur:
            sql = f"""
            DROP SCHEMA IF EXISTS transfer_from_viz CASCADE; 
            
            CREATE SCHEMA transfer_from_viz;
            
            IMPORT FOREIGN SCHEMA {viz_schema} LIMIT TO ({viz_table})
            FROM SERVER vizprc_db 
            INTO transfer_from_viz;
            
            SELECT * 
            INTO {egis_schema_and_table}
            FROM transfer_from_viz.{viz_table};
            
            DROP SCHEMA IF EXISTS transfer_from_viz CASCADE;
            """
            cur.execute(sql)
    egis_connection.close()
    print(f'Successfully copied {viz_schema_and_table} from the VIZ DB to {egis_schema_and_table} in the EGIS DB!')
