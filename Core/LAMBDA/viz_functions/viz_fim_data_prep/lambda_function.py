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

S3 = boto3.client('s3')

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
    fim_config_sql = fim_config['sql_file']
    target_table = fim_config['target_table']
    product = event['args']['product']['product']
    configuration = event['args']['product']['configuration']
    reference_time = event['args']['reference_time']
    reference_date = datetime.datetime.strptime(reference_time, "%Y-%m-%d %H:%M:%S")
    sql_replace = event['args']['sql_rename_dict']
    one_off = event['args'].get("hucs")
    process_by = fim_config.get('process_by', ['huc'])
    if fim_config.get("states_to_run"):
        states_to_run = fim_config.get("states_to_run")
    else:
        states_to_run = []
        
    reference_service = True if configuration == "reference" else False
    
    if sql_replace.get(target_table):
        target_table = sql_replace.get(target_table)
    
    print(f"Running FIM for {configuration} for {reference_time}")
    viz_db = database(db_type="viz")
    egis_db = database(db_type="egis")
    redshift_db = database(db_type="redshift")
    if reference_service:
        process_db = egis_db
    else:
        process_db = viz_db

    # Find the sql file, and replace any items in the dictionary
    sql_path = f'data_sql/{fim_config_sql}.sql'

    # Checks if all tables references in sql file exist and are updated (if applicable)
    # Raises a custom RequiredTableNotUpdated if not, which will be caught by viz_pipline
    # and invoke a retry
    viz_db.check_required_tables_updated(sql_path, sql_replace, reference_time, raise_if_false=True)

    sql = open(sql_path, 'r').read()
    # replace portions of SQL with any items in the dictionary (at least has reference_time)
    # sort the replace dictionary to have longer values upfront first
    sql_replace_sorted = sorted(sql_replace.items(), key = lambda item : len(item[1]), reverse = True)
    for word, replacement in sql_replace_sorted:
        sql = re.sub(re.escape(word), replacement, sql, flags=re.IGNORECASE).replace('utc', 'UTC')

    setup_db_table(target_table, reference_time, viz_db, process_db, sql_replace)
    
    # If only running select states, add additional where clauses to the SQL
    if len(states_to_run) > 0:
        additional_where_clauses = " AND (channels.state = '"
        for i, state in enumerate(states_to_run):
            additional_where_clauses += state
            if i+1 < len(states_to_run):
                additional_where_clauses += "' OR channels.state = '"
            else:
                additional_where_clauses += "')"
        sql += additional_where_clauses

    if "rfc" in fim_config_name:
        alias = 'max_forecast' if 'max_forecast' in sql else 'rnr'
        if sql.strip().endswith(';'):
            sql = sql.replace(';', f' group by {alias}.feature_id, streamflow_cms')
        else:
            sql += f" group by {alias}.feature_id, streamflow_cms"

    sql = sql.replace(";", "")
    
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
        
        # Parses the forecast key to get the necessary metadata for the output file
        date = reference_date.strftime("%Y%m%d")
        hour = reference_date.strftime("%H")

        # Load cached fim data from Redshift into the RDS table
        redshift_fim_table = target_table.replace("ingest", "fim")
        load_cached_fim_from_redshift(viz_db, target_table, redshift_fim_table)

        ras_publish_table = get_valid_ras2fim_models(sql, target_table, reference_time, viz_db, egis_db, reference_service)
        df_streamflows = get_features_for_HAND_processing(sql, ras_publish_table, viz_db)
        processing_groups = df_streamflows.groupby(process_by)

        print(f"Kicking off {len(processing_groups)} processing groups for {product} for {reference_time}")

        for group_vals, group_df in processing_groups:
            if one_off and group_vals not in one_off:
                continue
            if group_df.empty:
                continue
            if isinstance(group_vals, str):
                group_vals = [group_vals]

            csv_key = write_data_csv_file(product, fim_config_name, date, hour, group_vals, group_df)
        
        s3_keys = []
        df_streamflows = df_streamflows.drop_duplicates(process_by + ["huc8_branch"])
        df_streamflows_split = [df_split for df_split in np.array_split(df_streamflows[process_by + ["huc8_branch"]], 20) if not df_split.empty]

        for index, df in enumerate(df_streamflows_split):
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

        return_object = {
            'hucs_to_process': s3_keys,
            'data_bucket': PROCESSED_OUTPUT_BUCKET,
            'data_prefix': PROCESSED_OUTPUT_PREFIX
        }
    
    return return_object
    
    
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
        SQL = f"TRUNCATE TABLE {db_fim_table}; TRUNCATE TABLE {db_fim_table}_geo;"
        cur.execute(SQL)
    connection.close()
    
    return db_fim_table

def load_cached_fim_from_redshift(viz_db, db_fim_table, redshift_fim_table):
    template = f'templates_sql/cached_fim_insertion.sql'
    with open(template, 'r') as file:
        sql = file.read()
        sql = sql \
            .replace("{db_fim_table}", db_fim_table) \
            .replace("{redshift_fim_table}", redshift_fim_table)
        print(f"Copying {redshift_fim_table} from Redshift to {db_fim_table} on RDS")    
        with viz_db.get_db_connection() as connection:
            cur = connection.cursor()
            cur.execute(sql)
        connection.close()

def write_data_csv_file(product, fim_config_name, date, hour, identifiers, huc_data):
    '''
        Write the subsetted streamflow data to a csv so that the huc processing lambdas can grab it

        Args:
            huc(str): HUC that will be processed
            filename(str): Forecast file that was used
            huc_data(pandas.datafrm): Dataframe subsetted for the specific huc

        Returns:
            data_json_key(str): key (path) to the json file in the workspace folder
    '''
    s3_path_piece = '/'.join(identifiers)
    # Key for the csv file that will be stored in S3
    csv_key = f"{PROCESSED_OUTPUT_PREFIX}/{product}/{fim_config_name}/workspace/{date}/{hour}/data/{s3_path_piece}_data.csv"

    # Save the dataframe as a local netcdf file
    tmp_path_piece = '_'.join(identifiers)
    tmp_csv = f'/tmp/{tmp_path_piece}.csv'
    huc_data.to_csv(tmp_csv, index=False)

    # Upload the csv file into S3
    print(f"Uploading {csv_key}")
    S3.upload_file(tmp_csv, PROCESSED_OUTPUT_BUCKET, csv_key)
    os.remove(tmp_csv)

    return csv_key
    
def get_valid_ras2fim_models(streamflow_sql, db_fim_table, reference_time, viz_db, egis_db, reference_service):
    
    if "flow_based_catfim" in db_fim_table:
        ras_insertion_template = f'templates_sql/ras2fim_insertion_for_flow_based_catfim.sql'
    elif "stage_based_catfim" in db_fim_table:
        ras_insertion_template = f'templates_sql/ras2fim_insertion_for_stage_based_catfim.sql'
    else:
        ras_insertion_template = f'templates_sql/ras2fim_insertion.sql'
        
    ras_insertion_sql = open(ras_insertion_template, 'r').read()
    ras_insertion_sql = ras_insertion_sql \
        .replace("{streamflow_sql}", streamflow_sql) \
        .replace("{db_fim_table}", db_fim_table) \
        .replace("{reference_time}", reference_time)
    
    publish_table = db_fim_table
    if reference_service:
        table = db_fim_table.split('.')[-1]
        publish_table = f"publish.{table}"
        ras_insertion_sql = ras_insertion_sql.replace(db_fim_table, publish_table)

    print(f"Adding ras2fim models to {db_fim_table}")
        
    with viz_db.get_db_connection() as connection:
        cur = connection.cursor()
        cur.execute(ras_insertion_sql)
    connection.close()

    if reference_service:
        with viz_db.get_db_connection() as db_connection, db_connection.cursor() as cur:
            cur.execute(f"SELECT * FROM publish.{table} LIMIT 1")
            column_names = [desc[0] for desc in cur.description]
            columns = ', '.join(column_names)
        db_connection.close()
        
        print(f"Copying {publish_table} to {db_fim_table}")
        try: # Try copying the data
            copy_data_to_egis(egis_db, origin_table=f"vizprc_publish.{table}", dest_table=db_fim_table, columns=columns, add_oid=True) #Copy the publish table from the vizprc db to the egis db, using fdw
        except Exception as e: # If it doesn't work initially, try refreshing the foreign schema and try again.
            refresh_fdw_schema(egis_db, local_schema="vizprc_publish", remote_server="vizprc_db", remote_schema="publish") #Update the foreign data schema - we really don't need to run this all the time, but it's fast, so I'm trying it.
            copy_data_to_egis(egis_db, origin_table=f"vizprc_publish.{table}", dest_table=db_fim_table, columns=columns, add_oid=True) #Copy the publish table from the vizprc db to the egis db, using fdw
    
    return publish_table

def get_features_for_HAND_processing(streamflow_sql, db_fim_table, viz_db):
    
    if "flow_based_catfim" in db_fim_table:
        hand_features_template = f'templates_sql/hand_features_for_flow_based_catfim.sql'
    elif "stage_based_catfim" in db_fim_table:
        hand_features_template = f'templates_sql/hand_features_for_stage_based_catfim.sql'
    else:
        hand_features_template = f'templates_sql/hand_features.sql'
        
    hand_sql = open(hand_features_template, 'r').read()
    hand_sql = hand_sql \
        .replace("{streamflow_sql}", streamflow_sql) \
        .replace("{db_fim_table}", db_fim_table)
    
    print("Determing features to be processed by HAND")
    df_hand = viz_db.run_sql_in_db(hand_sql)
    
    return df_hand
    

def copy_data_to_egis(db, origin_table, dest_table, columns, add_oid=True, add_geom_index=True, update_srid=None):
    
    with db.get_db_connection() as db_connection, db_connection.cursor() as cur:
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
    with db_connection.close()
            
def refresh_fdw_schema(db, local_schema, remote_server, remote_schema):
    with db.get_db_connection() as db_connection, db_connection.cursor() as cur:
        sql = f"""
        DROP SCHEMA IF EXISTS {local_schema} CASCADE; 
        CREATE SCHEMA {local_schema};
        IMPORT FOREIGN SCHEMA {remote_schema} FROM SERVER {remote_server} INTO {local_schema};
        """
        cur.execute(sql)
    db_connection.close()
    print(f"---> Refreshed {local_schema} foreign schema.")