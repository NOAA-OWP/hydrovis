import boto3
import os
import datetime
import time
import re
import numpy as np
import pandas as pd

from viz_classes import database

PROCESSED_OUTPUT_BUCKET = os.environ['PROCESSED_OUTPUT_BUCKET']
PROCESSED_OUTPUT_PREFIX = os.environ['PROCESSED_OUTPUT_PREFIX']
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
    sql_replace = event['args']['sql_rename_dict']
    sql_replace.update({'target_table': target_table})
    if 'sql_find_replace' in fim_config:
        sql_replace.update(fim_config['sql_find_replace'])
    one_off = event['args'].get("hucs")
    process_by = fim_config.get('process_by', ['huc'])
    
    print(f"Running FIM for {configuration} for {reference_time}") 
    # Initilize the database class for relevant databases
    viz_db = database(db_type="viz") # we always need the vizprocessing database to get flows data.

    print("Determing features to be processed by HAND")
    # Query flows data from the vizprocessing database, using the SQL defined above.
    # TODO: Update this for RFC, CatFIM, and AEP, and Catchments services by adding the creation of flows tables to postprocess_sql
    hand_sql = open("templates_sql/hand_features.sql", 'r').read()
    hand_sql = hand_sql.replace("{db_fim_table}", target_table)
    df_streamflows = viz_db.run_sql_in_db(hand_sql)
    
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