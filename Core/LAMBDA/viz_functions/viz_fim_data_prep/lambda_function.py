import boto3
import os
import datetime
import numpy as np
import pandas as pd

from viz_classes import database

PROCESSED_OUTPUT_BUCKET = os.environ['PROCESSED_OUTPUT_BUCKET']
PROCESSED_OUTPUT_PREFIX = os.environ['PROCESSED_OUTPUT_PREFIX']
FIM_VERSION = os.environ['FIM_VERSION']
RAS2FIM_VERSION = os.environ['RAS2FIM_VERSION']

hand_processing_parallel_groups = 20

S3 = boto3.client('s3')

#################################################################################################################################################################
def lambda_handler(event, context):    
    #This runs within the fim_config map of the step function, once cached fim (hand and ras2fim) has already been loaded, in order to alocate hucs/reaches to the hand processing step function.
    if event['step'] == "setup_fim_config":
        return setup_huc_inundation(event)
    #This runs within the mapped hand processing step functions to get the hucs for the given iteration.
    else:
        return get_branch_iteration(event)
    
#################################################################################################################################################################
# This function runs at the top of a hand processing workflow, after cached fim has been loaded (from ras2fim and/or hand, via SQL in the postprocess_sql lambda function), and performs two main operations:
# 1. Query the vizprocessing database for flows to use for FIM (forecast flows for regurlar runs, recurrence flows for AEP FIM, rfc_categorical_flows for CATFIM)
#       - If a specific sql file is present in the flows_sql folder, the function will use that to query flows form the RDS db. If a file is not present, it will use a template file in the templates_sql folder.
# 2. Setup appropriate groups of HUC8s to delegate the FIM extent generation for those flows to the hand_processing step function.
#       - This function is also called within each huc processing group to get the branch interation, as noted in labmda_handler above.
def setup_huc_inundation(event):
    
    # Get relevant variables from the Step Function json
    fim_config = event['args']['fim_config']
    fim_config_name = fim_config['name']
    # fim_publish_db_type = fim_config['publish_db'] # TODO: Add this to step function only to pass to hand_processing?
    target_table = fim_config['target_table']
    product = event['args']['product']['product']
    configuration = event['args']['product']['configuration']
    reference_time = event['args']['reference_time']
    reference_date = datetime.datetime.strptime(reference_time, "%Y-%m-%d %H:%M:%S")
    date = reference_date.strftime("%Y%m%d")
    hour = reference_date.strftime("%H")
    one_off = event['args'].get("hucs")
    process_by = fim_config.get('process_by', ['huc'])
    
    print(f"Running FIM for {configuration} for {reference_time}") 
    # Initilize the database class for relevant databases
    viz_db = database(db_type="viz") # we always need the vizprocessing database to get flows data.

    # If a reference configuration, check to see if any preprocessing sql is needed (this currently does manual things, like reploading ras2fim data, which is copied to egis at the bottom of this function)
    if configuration == 'reference':
        preprocess_sql_file = os.path.join("reference_preprocessing_sql", fim_config_name + '.sql')
        if os.path.exists(preprocess_sql_file):
            print(f"Running {preprocess_sql_file} preprocess sql file.")
            preprocess_sql = open(preprocess_sql_file, 'r').read()
            preprocess_sql.replace('{fim_version}', FIM_VERSION)
            preprocess_sql.replace('{ras2fim_version_db}', RAS2FIM_VERSION.replace('.', '_'))
            viz_db.execute_sql(preprocess_sql)

    print("Determing features to be processed by HAND")
    # Query flows data from the vizprocessing database, using the SQL defined above.
    hand_features_sql_file = os.path.join("hand_features_sql", fim_config_name + '.sql')
    # If a SQL file exists for selecting hand features, use it.
    if os.path.exists(hand_features_sql_file):
        hand_sql = open(hand_features_sql_file, 'r').read()
    # Otherwise, use the template file
    else:
        hand_sql = open("templates_sql/hand_features.sql", 'r').read()
        hand_sql = hand_sql.replace("{db_fim_table}", target_table)
    
    # Using the sql defined above, pull features for running hand into a dataframe
    df_streamflows = viz_db.sql_to_dataframe(hand_sql)
    
    # Split reaches with flows into processing groups, and write two sets of csv files to S3 (we need to write to csvs to not exceed the limit of what can be passed in the step function):
    # This first loop splits up the number of huc8_branch combinations into X even 'hucs_to_process' groups, in order to parallel process groups in a step function map, and writes those to csv files on S3.
    s3_keys = []
    df_huc8_branches = df_streamflows.drop_duplicates(process_by + ["huc8_branch"])
    df_huc8_branches_split = [df_split for df_split in np.array_split(df_huc8_branches[process_by + ["huc8_branch"]], hand_processing_parallel_groups) if not df_split.empty]
    for index, df in enumerate(df_huc8_branches_split):
        # Key for the csv file that will be stored in S3
        csv_key = f"{PROCESSED_OUTPUT_PREFIX}/{product}/{fim_config_name}/workspace/{date}/{hour}/hucs_to_process_{index}.csv"
        s3_keys.append(csv_key)
    
        # Save the dataframe as a local netcdf file
        tmp_csv = f'/tmp/{product}.csv'
        df.to_csv(tmp_csv, index=False)
    
        # Upload the csv file into S3
        print(f"Uploading {csv_key}")
        S3.upload_file(tmp_csv, PROCESSED_OUTPUT_BUCKET, csv_key)
        os.remove(tmp_csv)
        
    # This second loop writes the actual reaches/flows data to a csv file for each huc8_branch, using the write_flows_data_csv_file function defined below.
    processing_groups = df_streamflows.groupby(process_by)
    print(f"{len(df_streamflows)} Total Features for {product} HAND Processing for Reference Time:{reference_time} - Setting up {len(processing_groups)} processing groups.")
    for group_vals, group_df in processing_groups:
        if one_off and group_vals not in one_off:
            continue
        if group_df.empty:
            continue
        if isinstance(group_vals, str):
            group_vals = [group_vals]
        csv_key = write_flows_data_csv_file(product, fim_config_name, date, hour, group_vals, group_df)

    return_object = {
        'hucs_to_process': s3_keys,
        'data_bucket': PROCESSED_OUTPUT_BUCKET,
        'data_prefix': PROCESSED_OUTPUT_PREFIX
    }

    # If a reference service, copy any cached data / setup the egis destination tables before hand processing is run.
    if configuration == 'reference':
        egis_db = database(db_type="egis")
        table = target_table.split('.')[-1]
        publish_table = f"publish.{table}"
        columns = None
        
        try:
            with viz_db.get_db_connection() as db_connection, db_connection.cursor() as cur:
                cur.execute(f"SELECT * FROM {publish_table} LIMIT 1")
                column_names = [desc[0] for desc in cur.description]
                columns = ', '.join(column_names)
            db_connection.close()
        except:
            pass
        
        if columns:
            print(f"Copying {publish_table} to {target_table}")
            try: # Try copying the data
                copy_data_to_egis(egis_db, origin_table=f"vizprc_publish.{table}", dest_table=target_table, columns=columns, add_oid=True, update_srid=3857) #Copy the publish table from the vizprc db to the egis db, using fdw
            except Exception as e: # If it doesn't work initially, try refreshing the foreign schema and try again.
                refresh_fdw_schema(egis_db, local_schema="vizprc_publish", remote_server="vizprc_db", remote_schema="publish") #Update the foreign data schema - we really don't need to run this all the time, but it's fast, so I'm trying it.
                copy_data_to_egis(egis_db, origin_table=f"vizprc_publish.{table}", dest_table=target_table, columns=columns, add_oid=True, update_srid=3857) #Copy the publish table from the vizprc db to the egis db, using fdw
        else:
            print("WARNING: Unable to copy {publish_table} to {target_table} because {publish_table} does not exist")

    return return_object

#################################################################################################################################################################
def write_flows_data_csv_file(product, fim_config_name, date, hour, identifiers, huc_data):
    s3_path_piece = '/'.join(identifiers)
    # Key for the csv file that will be stored in S3
    csv_key = f"{PROCESSED_OUTPUT_PREFIX}/{product}/{fim_config_name}/workspace/{date}/{hour}/data/{s3_path_piece}_data.csv"

    # Save the dataframe as a local netcdf file
    tmp_path_piece = '_'.join(identifiers)
    tmp_csv = f'/tmp/{tmp_path_piece}.csv'
    huc_data.to_csv(tmp_csv, index=False)

    # Upload the csv file into S3
    print(f"Uploading {csv_key} - {len(huc_data)} features.")
    S3.upload_file(tmp_csv, PROCESSED_OUTPUT_BUCKET, csv_key)
    os.remove(tmp_csv)

    return csv_key

#################################################################################################################################################################    
# This function loads a hucs_to_process csv file from S3 (which was generated in the first invokation of this function in the setup_huc_inundation function above.)
def get_branch_iteration(event):
    local_data_file = os.path.join("/tmp", os.path.basename(event['args']['huc_branches_to_process']))
    S3.download_file(event['args']['data_bucket'], event['args']['huc_branches_to_process'], local_data_file)
    df = pd.read_csv(local_data_file)
    df['huc'] = df['huc'].astype(str).str.zfill(6)
    os.remove(local_data_file)
    
    return_object = {
        "huc_branches_to_process": df.to_dict("records")
    }
    
    return return_object

#################################################################################################################################################################    
# This function sets up the data for a reference service fim run - e.g. AEP FIM - where hand processing is typically done directly against the egis database.
# This is necessary for cases like AEP FIM because Ras2FIM features are added prior to hand processing, so that data must be copied to the target egis
# tables before hand processing is run for the remaining features (see the hand_features sql files for aep fim)
def copy_data_to_egis(db, origin_table, dest_table, columns, add_oid=True, add_geom_index=True, update_srid=None):
    
    connection = db.get_db_connection()
    with connection:
        with connection.cursor() as cur:
            cur.execute(f"DROP TABLE IF EXISTS {dest_table};")
            cur.execute(f"SELECT {columns} INTO {dest_table} FROM {origin_table};")
        
            if add_oid:
                print(f"---> Adding an OID to the {dest_table}")
                cur.execute(f'ALTER TABLE {dest_table} ADD COLUMN OID SERIAL PRIMARY KEY;')
            if add_geom_index and "geom" in columns:
                print(f"---> Adding an spatial index to the {dest_table}")
                cur.execute(f'CREATE INDEX ON {dest_table} USING GIST (geom);')  # Add a spatial index
                if 'geom_xy' in columns:
                    cur.execute(f'CREATE INDEX ON {dest_table} USING GIST (geom_xy);')  # Add a spatial index to geometry point layer, if present.
            if update_srid and "geom" in columns:
                print(f"---> Updating SRID to {update_srid}")
                cur.execute(f"SELECT UpdateGeometrySRID('{dest_table.split('.')[0]}', '{dest_table.split('.')[1]}', 'geom', {update_srid});")
    connection.close()

#################################################################################################################################################################    
# This function drops and recreates a foreign data wrapper schema, so that table and column names are all up-to-date.     
def refresh_fdw_schema(db, local_schema, remote_server, remote_schema):
    connection = db.get_db_connection()
    with connection:
        with connection.cursor() as cur:
            sql = f"""
            DROP SCHEMA IF EXISTS {local_schema} CASCADE; 
            CREATE SCHEMA {local_schema};
            IMPORT FOREIGN SCHEMA {remote_schema} FROM SERVER {remote_server} INTO {local_schema};
            """
            cur.execute(sql)
    connection.close()
    print(f"---> Refreshed {local_schema} foreign schema.")