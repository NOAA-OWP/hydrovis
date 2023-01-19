import boto3
import re
import os
import datetime
import time
import json
import numpy as np

from viz_classes import database

FIM_DATA_BUCKET = os.environ['FIM_DATA_BUCKET']
FIM_PREFIX = f'fim_{os.environ["FIM_VERSION"].replace(".", "_")}/'

PROCESSED_OUTPUT_BUCKET = os.environ['PROCESSED_OUTPUT_BUCKET']
PROCESSED_OUTPUT_PREFIX = os.environ['PROCESSED_OUTPUT_PREFIX']


def lambda_handler(event, context):
    """
        The lambda handler is the function that is kicked off with the lambda. This function will take a forecast file,
        extract features with streamflows above 1.5 year threshold, and then kick off lambdas for each HUC with valid
        data.

        Args:
            event(event object): An event is a JSON-formatted document that contains data for a Lambda function to
                                 process
            context(object): Provides methods and properties that provide information about the invocation, function,
                             and runtime environment
    """
    fim_config = event['args']['fim_config']
    service_data = event['args']['service']
    reference_time = event['args']['reference_time']
    reference_date = datetime.datetime.strptime(reference_time, "%Y-%m-%d %H:%M:%S")
    service = service_data['service']
    configuration = service_data['configuration']
    sql_replace = event['args']['sql_rename_dict']
    one_off = event['args'].get("hucs")
    
    print(f"Running FIM for {configuration} for {reference_time}")
    db_type = "viz"
    viz_db = database(db_type=db_type)

    # Find the sql file, and replace any items in the dictionary
    sql_path = f'data_sql/{fim_config}.sql'
    sql = open(sql_path, 'r').read().lower()
    df_streamflows = viz_db.run_sql_in_db(sql)

    table = fim_config
    target_schema = "ingest"
    if fim_config.startswith("rf_"): #recurrence flow fim
        target_schema = "reference"
        db_type = "egis"
        target_table = f"{target_schema}.{table}"
    elif len(sql_replace) > 0: #past events
        target_schema = "archive"
        target_table = sql_replace[f"ingest.{fim_config}"]
    else: #everything else
        target_table = f"{target_schema}.{table}"

    setup_db_table(target_table, reference_time, db_type, sql_replace)
    
    if one_off:
        hucs_to_process = one_off
    else:
        hucs_to_process = df_streamflows['huc'].unique()
        
    print(f"Kicking off {len(hucs_to_process)} hucs for {service} for {reference_time}")

    for huc in hucs_to_process:
        huc_data = df_streamflows[df_streamflows['huc'] == huc]  # get data for this huc only
        
        if huc_data.empty:
            continue
        
        write_data_csv_file(service, fim_config, huc, reference_date, huc_data)
        
    print(f"Creating file for huc processing for {service} for {reference_time}")
    df_streamflows = df_streamflows.drop_duplicates("huc8_branch")
    df_streamflows = df_streamflows[["huc8_branch", "huc"]]
    df_streamflows['db_fim_table'] = target_table
    df_streamflows['reference_time'] = reference_time
    df_streamflows['service'] = service
    df_streamflows['fim_config'] = fim_config
    df_streamflows['data_bucket'] = PROCESSED_OUTPUT_BUCKET
    df_streamflows['data_prefix'] = PROCESSED_OUTPUT_PREFIX
    
    s3 = boto3.client('s3')

    # Parses the forecast key to get the necessary metadata for the output file
    date = reference_date.strftime("%Y%m%d")
    hour = reference_date.strftime("%H")

    # Key for the csv file that will be stored in S3
    csv_key = f"{PROCESSED_OUTPUT_PREFIX}/{service}/{fim_config}/workspace/{date}/{hour}/hucs_to_process.csv"

    # Save the dataframe as a local netcdf file
    tmp_csv = f'/tmp/{service}.csv'
    df_streamflows.to_csv(tmp_csv, index=False)

    # Upload the csv file into S3
    print(f"Uploading {csv_key}")
    s3.upload_file(tmp_csv, PROCESSED_OUTPUT_BUCKET, csv_key)
    os.remove(tmp_csv)
    
    return_object = {
        'huc_processing_key': csv_key,
        'huc_processing_bucket': PROCESSED_OUTPUT_BUCKET
    }
    
    return return_object


def setup_db_table(db_fim_table, reference_time, db_type="viz", sql_replace=None):
    """
        Sets up the necessary tables in a postgis data for later ingest from the huc processing functions

        Args:
            configuration(str): service configuration for the service being ran (i.e. srf, srf_hi, etc)
            reference_time(str): Reference time of the data being ran
            sql_replace(dict): An optional dictionary by which to use to create a new table if needed
    """
    index_name = f"idx_{db_fim_table.split('.')[-1:].pop()}_hydro_id"
    db_schema = db_fim_table.split('.')[0]

    print(f"Setting up {db_fim_table}")
    # Connect to the postgis DB
    viz_db = database(db_type="viz")
    if db_type == "viz":
        process_db = viz_db
    else:
        process_db = database(db_type=db_type)
        
    with viz_db.get_db_connection() as connection:
        cur = connection.cursor()

        # Add a row to the ingest status table indicating that an import has started.
        SQL = f"INSERT INTO admin.ingest_status (target, reference_time, status, update_time) " \
              f"VALUES ('{db_fim_table}', '{reference_time}', 'Import Started', " \
              f"'{datetime.datetime.fromtimestamp(time.time()).strftime('%Y-%m-%d %H:%M:%S')}')"
        cur.execute(SQL)

    with process_db.get_db_connection() as connection:
        cur = connection.cursor()

         # See if the target table exists #TODO: Ensure table exists would make a good helper function
        cur.execute(f"SELECT EXISTS (SELECT FROM pg_tables WHERE schemaname = '{db_fim_table.split('.')[0]}' AND tablename = '{db_fim_table.split('.')[1]}');")
        table_exists = cur.fetchone()[0]
        
        # If the target table doesn't exist, create one basd on the sql_replace dict.
        if not table_exists:
            print(f"--> {db_fim_table} does not exist. Creating now.")
            original_table = list(sql_replace.keys())[list(sql_replace.values()).index(db_fim_table)] #ToDo: error handling if not in list
            cur.execute(f"DROP TABLE IF EXISTS {db_fim_table}; CREATE TABLE {db_fim_table} (LIKE {original_table})")
            connection.commit()

        # Drop the existing index on the target table
        print("Dropping target table index (if exists).")
        SQL = f"DROP INDEX IF EXISTS {db_schema}.{index_name};"
        cur.execute(SQL)

        # Truncate all records.
        print("Truncating target table.")
        SQL = f"TRUNCATE TABLE {db_fim_table};"
        cur.execute(SQL)
        connection.commit()
    
    return db_fim_table

def write_data_csv_file(service, fim_config, huc, reference_date, huc_data):
    '''
        Write the subsetted streamflow data to a csv so that the huc processing lambdas can grab it

        Args:
            huc(str): HUC that will be processed
            filename(str): Forecast file that was used
            huc_data(pandas.datafrm): Dataframe subsetted for the specific huc

        Returns:
            data_json_key(str): key (path) to the json file in the workspace folder
    '''
    s3 = boto3.client('s3')

    # Parses the forecast key to get the necessary metadata for the output file
    date = reference_date.strftime("%Y%m%d")
    hour = reference_date.strftime("%H")

    # Key for the csv file that will be stored in S3
    csv_key = f"{PROCESSED_OUTPUT_PREFIX}/{service}/{fim_config}/workspace/{date}/{hour}/data/{huc}_data.csv"

    # Save the dataframe as a local netcdf file
    tmp_csv = f'/tmp/{huc}.csv'
    huc_data.to_csv(tmp_csv, index=False)

    # Upload the csv file into S3
    print(f"Uploading {csv_key}")
    s3.upload_file(tmp_csv, PROCESSED_OUTPUT_BUCKET, csv_key)
    os.remove(tmp_csv)

    return csv_key
