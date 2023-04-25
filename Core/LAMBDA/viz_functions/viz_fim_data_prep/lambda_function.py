import boto3
import os
import datetime
import time
import numpy as np
import pandas as pd

from viz_classes import database

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
    
    if event['step'] == "setup_fim_config":
        return setup_huc_inundation(event)
    else:
        return get_branch_iteration(event)
    
def setup_huc_inundation(event):
    fim_config = event['args']['fim_config']
    fim_config_name = fim_config['name']
    target_table = fim_config['target_table']
    product = event['args']['product']['product']
    configuration = event['args']['product']['configuration']
    reference_time = event['args']['reference_time']
    reference_date = datetime.datetime.strptime(reference_time, "%Y-%m-%d %H:%M:%S")
    sql_replace = event['args']['sql_rename_dict']
    one_off = event['args'].get("hucs")
    
    if sql_replace.get(target_table):
        target_table = sql_replace.get(target_table)
    
    print(f"Running FIM for {configuration} for {reference_time}")
    viz_db = database(db_type="viz")
    if configuration == "reference":
        process_db = database(db_type="egis")
    else:
        process_db = viz_db

    # Find the sql file, and replace any items in the dictionary
    sql_path = f'data_sql/{fim_config_name}.sql'
    sql = open(sql_path, 'r').read().lower()

    setup_db_table(target_table, reference_time, viz_db, process_db, sql_replace)
    
    fim_type = fim_config['fim_type']
    if fim_type == "coastal":
        print("Running coastal SCHISM workflow")
        hucs = viz_db.run_sql_in_db(sql)
        hucs = list(hucs['huc'].values)
    
        return_object = {
            'hucs_to_process': hucs,
            'data_bucket': PROCESSED_OUTPUT_BUCKET,
            'data_prefix': PROCESSED_OUTPUT_PREFIX
        }
    else:
        print("Running inland HAND workflow")
        df_streamflows = viz_db.run_sql_in_db(sql)

        if one_off:
            hucs_to_process = one_off
        else:
            hucs_to_process = df_streamflows['huc'].unique()
            
        print(f"Kicking off {len(hucs_to_process)} hucs for {product} for {reference_time}")

        df_streamflows['data_key'] = None
        for huc in hucs_to_process:
            huc_data = df_streamflows[df_streamflows['huc'] == huc]  # get data for this huc only
            
            if huc_data.empty:
                continue
            
            csv_key = write_data_csv_file(product, fim_config_name, huc, reference_date, huc_data)
            df_streamflows.loc[df_streamflows['huc'] == huc, 'data_key'] = csv_key
            
        s3 = boto3.client('s3')

        # Parses the forecast key to get the necessary metadata for the output file
        date = reference_date.strftime("%Y%m%d")
        hour = reference_date.strftime("%H")
        
        s3_keys = []
        df_streamflows = df_streamflows.drop_duplicates("huc8_branch")
        df_streamflows_split = np.array_split(df_streamflows[["huc8_branch", "huc", "data_key"]], 20)
        for index, df in enumerate(df_streamflows_split):
            # Key for the csv file that will be stored in S3
            csv_key = f"{PROCESSED_OUTPUT_PREFIX}/{product}/{fim_config_name}/workspace/{date}/{hour}/hucs_to_process_{index}.csv"
            s3_keys.append(csv_key)
        
            # Save the dataframe as a local netcdf file
            tmp_csv = f'/tmp/{product}.csv'
            df.to_csv(tmp_csv, index=False)
        
            # Upload the csv file into S3
            print(f"Uploading {csv_key}")
            s3.upload_file(tmp_csv, PROCESSED_OUTPUT_BUCKET, csv_key)
            os.remove(tmp_csv)

        return_object = {
            'hucs_to_process': s3_keys,
            'data_bucket': PROCESSED_OUTPUT_BUCKET,
            'data_prefix': PROCESSED_OUTPUT_PREFIX
        }
    
    return return_object
    
    
def get_branch_iteration(event):
    s3 = boto3.client("s3")
    print(event)
    local_data_file = os.path.join("/tmp", os.path.basename(event['args']['huc_branches_to_process']))
    s3.download_file(event['args']['data_bucket'], event['args']['huc_branches_to_process'], local_data_file)
    df = pd.read_csv(local_data_file)
    df['huc'] = df['huc'].astype(str).str.zfill(6)
    os.remove(local_data_file)
    
    return_object = {
        "huc_branches_to_process": df[["huc8_branch", "huc"]].to_dict("records")
    }
    
    return return_object


def setup_db_table(db_fim_table, reference_time, viz_db, process_db, sql_replace=None):
    """
        Sets up the necessary tables in a postgis data for later ingest from the huc processing functions

        Args:
            configuration(str): product configuration for the product being ran (i.e. srf, srf_hi, etc)
            reference_time(str): Reference time of the data being ran
            sql_replace(dict): An optional dictionary by which to use to create a new table if needed
    """
    index_name = f"idx_{db_fim_table.split('.')[-1:].pop()}_hydro_id"
    db_schema = db_fim_table.split('.')[0]

    print(f"Setting up {db_fim_table}")
        
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

def write_data_csv_file(product, fim_config, huc, reference_date, huc_data):
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
    csv_key = f"{PROCESSED_OUTPUT_PREFIX}/{product}/{fim_config}/workspace/{date}/{hour}/data/{huc}_data.csv"

    # Save the dataframe as a local netcdf file
    tmp_csv = f'/tmp/{huc}.csv'
    huc_data.to_csv(tmp_csv, index=False)

    # Upload the csv file into S3
    print(f"Uploading {csv_key}")
    s3.upload_file(tmp_csv, PROCESSED_OUTPUT_BUCKET, csv_key)
    os.remove(tmp_csv)

    return csv_key
