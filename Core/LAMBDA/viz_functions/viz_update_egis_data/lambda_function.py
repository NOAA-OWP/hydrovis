import boto3
import os
from viz_classes import database, s3_file
from viz_lambda_shared_funcs import gen_dict_extract
from datetime import datetime, timedelta

###################################
def lambda_handler(event, context):
    cache_bucket = os.environ['CACHE_BUCKET']
    step = event['step']
    job_type = event['args']['job_type']
    reference_time = datetime.strptime(event['args']['reference_time'], '%Y-%m-%d %H:%M:%S')
    reference_date = reference_time.strftime('%Y%m%d')
    reference_hour_min = reference_time.strftime('%H%M')
    
    # Don't want to run for reference products because they already exist in the EGIS DB
    if event['args']['product']['configuration'] == "reference":
        return
    
    ################### Unstage EGIS Tables ###################
    if "unstage" in step:
        if job_type == "past_event":
            return
        elif step == "unstage_db_tables":
            print(f"Unstaging tables for {event['args']['product']['product']}")
            target_tables = list(gen_dict_extract("target_table", event['args']))
            all_single_tables = [table for table in target_tables if type(table) is not list]
            all_list_tables = [table for table in target_tables if type(table) is list]
            all_list_tables = [table for table_list in all_list_tables for table in table_list]
            
            all_tables = all_single_tables + all_list_tables
            publish_tables = [table for table in all_tables if table.startswith("publish")]
            dest_tables = [f"services.{table.split('.')[1]}" for table in publish_tables]

            egis_db = database(db_type="egis")
            unstage_db_tables(egis_db, dest_tables)
        elif step == "unstage_rasters":
            ################### Move Rasters ###################
            print(f"Moving and caching rasters for {event['args']['product']['product']}")
            s3 = boto3.resource('s3')
            s3_bucket = event['args']['raster_output_bucket']
            output_raster_workspace = list(event['args']['raster_output_workspace'].values())[0]
            
            mrf_extensions = ["idx", "til", "mrf", "mrf.aux.xml"]
            product_name = event['args']['product']['product']
            published_format = event['args']['product'].get('published_format', 'mrf')
            
            print(f"Moving and caching rasters in {output_raster_workspace}")
            output_raster_workspace = f"{output_raster_workspace}/tif"
                
            # Getting any sub configs such as fim_configs
            product_sub_config = output_raster_workspace.split(product_name,1)[1]
            product_sub_config = product_sub_config.split(reference_date,1)[0][1:-1]
            processing_prefix = output_raster_workspace.split(reference_date,1)[0][:-1]

            if product_sub_config:
                cache_path = f"viz_cache/{reference_date}/{reference_hour_min}/{product_name}/{product_sub_config}"
            else:
                cache_path = f"viz_cache/{reference_date}/{reference_hour_min}/{product_name}"

            workspace_rasters = list_s3_files(s3_bucket, output_raster_workspace)
            for s3_key in workspace_rasters:
                s3_object = {"Bucket": s3_bucket, "Key": s3_key}
                s3_filename = os.path.basename(s3_key)
                s3_extension = os.path.splitext(s3_filename)[1]
                cache_key = f"{cache_path}/{s3_filename}"
    
                print(f"Caching {s3_key} at {cache_key}")
                s3.meta.client.copy(s3_object, s3_bucket, cache_key)

                if published_format == 'tif' and job_type == 'auto':
                    tif_published_key = f"{processing_prefix}/published/{s3_filename}"
                    print(f"Moving {s3_object} to published location at {tif_published_key}")
                    s3.meta.client.copy(s3_object, s3_bucket, tif_published_key)
                elif published_format == 'mrf':
                    raster_name = s3_filename.replace(s3_extension, "")
                    mrf_workspace_prefix = s3_key.replace("/tif/", "/mrf/").replace(s3_extension, "")
                    published_prefix = f"{processing_prefix}/published/{raster_name}"
                    
                    if s3_extension == '.tif':
                        process_extensions = mrf_extensions
                    else:
                        process_extensions = [s3_extension[1:]]

                    for extension in process_extensions:
                        mrf_workspace_raster = {"Bucket": s3_bucket, "Key": f"{mrf_workspace_prefix}.{extension}"}
                        mrf_published_raster = f"{published_prefix}.{extension}"

                        if job_type == 'auto':
                            print(f"Moving {mrf_workspace_prefix}.{extension} to published location at {mrf_published_raster}")
                            s3.meta.client.copy(mrf_workspace_raster, s3_bucket, mrf_published_raster)
                    
                        print("Deleting a mrf workspace raster")
                        s3.Object(s3_bucket, f"{mrf_workspace_prefix}.{extension}").delete()
        
        return True
    
    ################### Stage EGIS Tables ###################
    elif step == "update_summary_data":
        tables =  event['args']['postprocess_summary']['target_table']
    elif step == "update_fim_config_data":
        if not event['args']['fim_config'].get('postprocess'):
            return
        
        tables = [event['args']['fim_config']['postprocess']['target_table']]
    else:
        tables = [event['args']['postprocess_sql']['target_table']]
    
    # Set the viz schema to work with based on the job type    
    if job_type == 'auto':
        viz_schema = 'publish'
    elif job_type == 'past_event':
        viz_schema = 'archive'
        
    # Get the table names without the schemas
    tables = [table.split(".")[1] for table in tables if table.split(".")[0]==viz_schema]
    
    ## For Staging and Caching - Loop through all the tables relevant to the current step
    for table in tables:
        staged_table = f"{table}_stage"
        viz_db = database(db_type="viz")
        egis_db = database(db_type="egis")
        
        # Get columns of the table
        connection = viz_db.get_db_connection()
        with connection:
            with connection.cursor() as cur:
                cur.execute(f"SELECT * FROM {viz_schema}.{table} LIMIT 1")
                column_names = [desc[0] for desc in cur.description]
        connection.close()

        columns = ', '.join(column_names)
            
        if job_type == 'auto':
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
    aws_region = os.environ['AWS_REGION']
    columns = columns.replace('geom', 'ST_AsText(geom) AS geom')

    connection = db.get_db_connection()
    with connection:
        with connection.cursor() as cur:
            cur.execute(f"SELECT * FROM aws_s3.query_export_to_s3('SELECT {columns} FROM {schema}.{table}', aws_commons.create_s3_uri('{cache_bucket}','{s3_key}','{aws_region}'), options :='format csv , HEADER true');")
    connection.close()

    print(f"---> Wrote csv cache data from {schema}.{table} to {cache_bucket}/{s3_key}")
    return s3_key

###################################
# This function stages a publish data table within a db (or across databases using foreign data wrapper)
def stage_db_table(db, origin_table, dest_table, columns, add_oid=True, add_geom_index=True, update_srid=None):
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

###################################
# This function unstages a list of publish data tables within a db (or across databases using foreign data wrapper)
def unstage_db_tables(db, dest_tables):
    connection = db.get_db_connection()
    with connection:
        for dest_table in dest_tables:
            dest_final_table = dest_table
            dest_final_table_name = dest_final_table.split(".")[1]
            dest_table = f"{dest_table}_stage"

            with connection.cursor() as cur:
                print(f"---> Renaming {dest_table} to {dest_final_table}")
                cur.execute(f'DROP TABLE IF EXISTS {dest_final_table};')  # Drop the published table if it exists
                cur.execute(f'ALTER TABLE {dest_table} RENAME TO {dest_final_table_name};')  # Rename the staged table
            connection.commit()
    connection.close()
        
###################################
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
    
##################################
def list_s3_files(bucket, prefix):
    s3 = boto3.client('s3')
    files = []
    paginator = s3.get_paginator('list_objects_v2')
    for result in paginator.paginate(Bucket=bucket, Prefix=prefix):
        if not result['KeyCount']:
            continue
        
        for key in result['Contents']:
            # Skip folders
            if not key['Key'].endswith('/'):
                files.append(key['Key'])

    if not files:
        print(f"No files found at {bucket}/{prefix}")
    return files