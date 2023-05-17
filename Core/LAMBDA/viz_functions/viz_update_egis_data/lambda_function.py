import boto3
import os
from viz_classes import database
from viz_lambda_shared_funcs import gen_dict_extract
from datetime import datetime, timedelta

###################################
def lambda_handler(event, context):
    cache_bucket = os.environ['CACHE_BUCKET']
    step = event['step']
    job_type = event['args']['job_type']
    reference_time = datetime.strptime(event['args']['reference_time'], '%Y-%m-%d %H:%M:%S')
    
    # Don't want to run for reference products because they already exist in the EGIS DB
    if event['args']['product']['configuration'] == "reference":
        return
    
    ################### Unstage EGIS Tables ###################
    if step == "unstage" and job_type != "past_event":
        target_tables = list(gen_dict_extract("target_table", event['args']))
        all_single_tables = [table for table in target_tables if type(table) is not list]
        all_list_tables = [table for table in target_tables if type(table) is list]
        all_list_tables = [table for table_list in all_list_tables for table in table_list]
        
        all_tables = all_single_tables + all_list_tables
        publish_tables = [table for table in all_tables if table.startswith("publish")]
        dest_tables = [f"services.{table.split('.')[1]}" for table in publish_tables]

        egis_db = database(db_type="egis")
        unstage_db_tables(egis_db, dest_tables)

        ################### Move Rasters ###################
        if event['args']['product']['raster_outputs'].get('output_raster_workspaces'):
            s3 = boto3.resource('s3')
            output_raster_workspaces = [workspace for config, workspace in event['args']['product']['raster_outputs']['output_raster_workspaces'].items()]
            mrf_extensions = ["idx", "til", "mrf", "mrf.aux.xml"]
            
            product_name = event['args']['product']['product']
            s3_bucket = event['args']['product']['raster_outputs']['output_bucket']
            
            for output_raster_workspace in output_raster_workspaces:
                output_raster_workspace = f"{output_raster_workspace}/tif"
                workspace_rasters = list_s3_files(s3_bucket, output_raster_workspace)
                for s3_key in workspace_rasters:
                    s3_object = {"Bucket": s3_bucket, "Key": s3_key}
                    
                    processing_prefix = s3_key.split(product_name,1)[0]
                    cache_path = s3_key.split(product_name, 1)[1].replace('/workspace/tif', '')
                    cache_key = f"{processing_prefix}{product_name}/cache{cache_path}"
        
                    print(f"Caching {s3_key} at {cache_key}")
                    s3.meta.client.copy(s3_object, s3_bucket, cache_key)
                    
                    print("Deleting tif workspace raster")
                    s3.Object(s3_bucket, s3_key).delete()
        
                    raster_name = os.path.basename(s3_key).replace(".tif", "")
                    mrf_workspace_prefix = s3_key.replace("/tif/", "/mrf/").replace(".tif", "")
                    published_prefix = f"{processing_prefix}{product_name}/published/{raster_name}"
                    
                    for extension in mrf_extensions:
                        mrf_workspace_raster = {"Bucket": s3_bucket, "Key": f"{mrf_workspace_prefix}.{extension}"}
                        mrf_published_raster = f"{published_prefix}.{extension}"
                        
                        if job_type == 'auto':
                            print(f"Moving {mrf_workspace_prefix}.{extension} to published location at {mrf_published_raster}")
                            s3.meta.client.copy(mrf_workspace_raster, s3_bucket, mrf_published_raster)
                    
                        print("Deleting a mrf workspace raster")
                        s3.Object(s3_bucket, f"{mrf_workspace_prefix}.{extension}").delete()
        
        return True
    
    ################### Stage EGIS Tables ###################
    if step == "update_summary_data":
        tables =  event['args']['postprocess_summary']['target_table']
    elif step == "update_fim_config_data":
        if not event['args']['fim_config'].get('postprocess'):
            return
        
        tables = [event['args']['fim_config']['postprocess']['target_table']]
    else:
        tables = [event['args']['postprocess_sql']['target_table']]
        
    tables = [table.split(".")[1] for table in tables if table.split(".")[0]=="publish"]
    
    ## For Staging and Caching - Loop through all the tables relevant to the current step
    for table in tables:
        staged_table = f"{table}_stage"
        viz_db = database(db_type="viz")
        egis_db = database(db_type="egis")
            
        if job_type == 'auto':
            viz_schema = 'publish'
            
            # Get columns of the table
            with viz_db.get_db_connection() as db_connection, db_connection.cursor() as cur:
                    cur.execute(f"SELECT * FROM publish.{table} LIMIT 1")
                    column_names = [desc[0] for desc in cur.description]
                    columns = ', '.join(column_names)
            
            # Copy data to EGIS - THIS CURRENTLY DOES NOT WORK IN DEV DUE TO REVERSE PEERING NOT FUNCTIONING - it will copy the viz TI table.
            try: # Try copying the data
                stage_db_table(egis_db, origin_table=f"vizprc_publish.{table}", dest_table=f"services.{staged_table}", columns=columns, add_oid=True, add_geom_index=True, update_srid=3857) #Copy the publish table from the vizprc db to the egis db, using fdw
            except Exception as e: # If it doesn't work initially, try refreshing the foreign schema and try again.
                refresh_fdw_schema(egis_db, local_schema="vizprc_publish", remote_server="vizprc_db", remote_schema=viz_schema) #Update the foreign data schema - we really don't need to run this all the time, but it's fast, so I'm trying it.
                stage_db_table(egis_db, origin_table=f"vizprc_publish.{table}", dest_table=f"services.{staged_table}", columns=columns, add_oid=True, add_geom_index=True, update_srid=3857) #Copy the publish table from the vizprc db to the egis db, using fdw

            cache_data_on_s3(viz_db, viz_schema, table, reference_time, cache_bucket, columns)

        elif job_type == 'past_event':
            viz_schema = 'archive'
            cache_data_on_s3(viz_db, viz_schema, table, reference_time, cache_bucket, columns)
    
    return True

###################################
# This function uses the aws_s3 postgresql extension to directly write csv files of the specified table to S3. Geometry is stored in WKT.
def cache_data_on_s3(db, schema, table, reference_time, cache_bucket, columns, retention_days=30):
    ref_day = f"{reference_time.strftime('%Y%m%d')}"
    ref_hour = f"{reference_time.strftime('%H%M')}"
    s3_key = f"viz_cache/{ref_day}/{ref_hour}/{table}.csv"
    with db.get_db_connection() as db_connection, db_connection.cursor() as cur:
            columns = columns.replace('geom', 'ST_AsText(geom) AS geom')
            cur.execute(f"SELECT * FROM aws_s3.query_export_to_s3('SELECT {columns} FROM {schema}.{table}', aws_commons.create_s3_uri('{cache_bucket}','{s3_key}','us-east-1'), options :='format csv , HEADER true');")
    print(f"---> Wrote csv cache data from {schema}.{table} to {cache_bucket}/{s3_key}")
    return s3_key

###################################
# This function stages a publish data table within a db (or across databases using foreign data wrapper)
def stage_db_table(db, origin_table, dest_table, columns, add_oid=True, add_geom_index=True, update_srid=None):
    
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

###################################
# This function unstages a list of publish data tables within a db (or across databases using foreign data wrapper)
def unstage_db_tables(db, dest_tables):
    
    with db.get_db_connection() as db_connection, db_connection.cursor() as cur:
        
        for dest_table in dest_tables:
            dest_final_table = dest_table
            dest_final_table_name = dest_final_table.split(".")[1]
            dest_table = f"{dest_table}_stage"
            
            print(f"---> Renaming {dest_table} to {dest_final_table}")
            cur.execute(f'DROP TABLE IF EXISTS {dest_final_table};')  # Drop the published table if it exists
            cur.execute(f'ALTER TABLE {dest_table} RENAME TO {dest_final_table_name};')  # Rename the staged table
        
###################################
# This function drops and recreates a foreign data wrapper schema, so that table and column names are all up-to-date.     
def refresh_fdw_schema(db, local_schema, remote_server, remote_schema):
    with db.get_db_connection() as db_connection, db_connection.cursor() as cur:
        sql = f"""
        DROP SCHEMA IF EXISTS {local_schema} CASCADE; 
        CREATE SCHEMA {local_schema};
        IMPORT FOREIGN SCHEMA {remote_schema} FROM SERVER {remote_server} INTO {local_schema};
        """
        cur.execute(sql)
    print(f"---> Refreshed {local_schema} foreign schema.")
    
##################################
def list_s3_files(bucket, prefix):
    s3 = boto3.client('s3')
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
