import boto3
import os
from viz_classes import database, s3_file
from datetime import datetime, timedelta

###################################
def lambda_handler(event, context):
    cache_bucket = os.environ['CACHE_BUCKET']
    step = event['step']
    job_type = event['args']['job_type']
    reference_time = datetime.strptime(event['args']['reference_time'], '%Y-%m-%d %H:%M:%S')
    service_server = event['args']['service']['egis_server']

    # Don't want to run for reference services because they already exist in the EGIS DB
    if event['args']['service']['configuration'] == "reference":
        return
    
    if step == "update_summary_data":
        table = event['args']['postprocess_summary']
    else:
        table = event['args']['map_item']
    
    ################### Vector Services ###################
    if service_server == "server":
        viz_db = database(db_type="viz")
        egis_db = database(db_type="egis")
        
        if job_type == 'auto':
            viz_schema = 'publish'
            # Copy data to EGIS - THIS CURRENTLY DOES NOT WORK IN DEV DUE TO REVERSE PEERING NOT FUNCTIONING - it will copy the viz TI table.
            try: # Try copying the data
                publish_db_table(egis_db, origin_table=f"vizprc_publish.{table}", dest_table=f"services.{table}", stage=True, add_oid=True, add_geom_index=True) #Copy the publish table from the vizprc db to the egis db, using fdw
                egis_db.run_sql_in_db(f"SELECT UpdateGeometrySRID('services', '{table}', 'geom', 3857);") #Update srid - not sure we need this anymore... but it's fast, so I'm leaving it for now.
            except Exception as e: # If it doesn't work initially, try refreshing the foreign schema and try again.
                refresh_fdw_schema(egis_db, local_schema="vizprc_publish", remote_server="vizprc_db", remote_schema=viz_schema) #Update the foreign data schema - we really don't need to run this all the time, but it's fast, so I'm trying it.
                publish_db_table(egis_db, origin_table=f"vizprc_publish.{table}", dest_table=f"services.{table}", stage=True, add_oid=True, add_geom_index=True) #Copy the publish table from the vizprc db to the egis db, using fdw
                egis_db.run_sql_in_db(f"SELECT UpdateGeometrySRID('services', '{table}', 'geom', 3857);") #Update srid - not sure we need this anymore... but it's fast, so I'm leaving it for now.
            cached_file = cache_data_on_s3(viz_db, viz_schema, table, reference_time, cache_bucket)
            cleanup_cache(cache_bucket, table, reference_time)

        elif job_type == 'past_event':
            viz_schema = 'archive'
            cache_data_on_s3(viz_db, viz_schema, table, reference_time, cache_bucket)
   
   ################### Image Services ###################
    else:
        if job_type == 'auto':
            viz_schema = 'publish'
            viz_db = database(db_type="viz")
            egis_db = database(db_type="egis")
            service_name = event['args']['service']['service']
            # Copy the 1-row metadata table to EGIS - THIS CURRENTLY DOES NOT WORK IN DEV DUE TO REVERSE PEERING NOT FUNCTIONING - it will copy the viz TI table.
            try: # Try copying the data
                publish_db_table(egis_db, origin_table=f"vizprc_publish.{table}", dest_table=f"services.{table}", stage=True, add_oid=True, add_geom_index=False) #Copy the publish table from the vizprc db to the egis db, using fdw
            except Exception as e:  # If it doesn't work initially, try refreshing the foreign schema and try again.
                refresh_fdw_schema(egis_db, local_schema="vizprc_publish", remote_server="vizprc_db", remote_schema=viz_schema) #Update the foreign data schema - we really don't need to run this all the time, but it's fast, so I'm trying it.
                publish_db_table(egis_db, origin_table=f"vizprc_publish.{table}", dest_table=f"services.{table}", stage=True, add_oid=True, add_geom_index=False) #Copy the publish table from the vizprc db to the egis db, using fdw
            
        s3 = boto3.resource('s3')
        workspace_rasters = event['args']['output_rasters']
        service_name = event['args']['service']['service']
        
        mrf_extensions = ["idx", "til", "mrf", "mrf.aux.xml"]
        s3_bucket = event['args']['output_bucket']
        
        for s3_key in workspace_rasters:
            s3_object = {"Bucket": s3_bucket, "Key": s3_key}
            
            processing_prefix = s3_key.split(service_name,1)[0]
            cache_path = s3_key.split(service_name, 1)[1].replace('/workspace/tif', '')
            cache_key = f"{processing_prefix}{service_name}/cache{cache_path}"

            print(f"Caching {s3_key} at {cache_key}")
            s3.meta.client.copy(s3_object, s3_bucket, cache_key)
            
            print("Deleting tif workspace raster")
            s3.Object(s3_bucket, s3_key).delete()

            raster_name = os.path.basename(s3_key).replace(".tif", "")
            mrf_workspace_prefix = s3_key.replace("/tif/", "/mrf/").replace(".tif", "")
            published_prefix = f"{processing_prefix}{service_name}/published/{raster_name}"
            
            for extension in mrf_extensions:
                mrf_workspace_raster = {"Bucket": s3_bucket, "Key": f"{mrf_workspace_prefix}.{extension}"}
                mrf_published_raster = f"{published_prefix}.{extension}"
                
                if job_type == 'auto':
                    print(f"Moving {mrf_workspace_prefix}.{extension} to published location at {mrf_published_raster}")
                    s3.meta.client.copy(mrf_workspace_raster, s3_bucket, mrf_published_raster)
            
                print("Deleting a mrf workspace raster")
                s3.Object(s3_bucket, f"{mrf_workspace_prefix}.{extension}").delete()
    
    return True

###################################
# This function uses the aws_s3 postgresql extension to directly write csv files of the specified table to S3. Geometry is stored in WKT.
def cache_data_on_s3(db, schema, table, reference_time, cache_bucket, retention_days=30):
    ref_day = f"{reference_time.strftime('%Y%m%d')}"
    ref_hour = f"{reference_time.strftime('%H%M')}"
    s3_key = f"viz_cache/{ref_day}/{ref_hour}/{table}.csv"
    with db.get_db_connection() as connection:
        with connection.cursor() as curs:
            curs.execute(f"SELECT * FROM {schema}.{table} LIMIT 1")
            column_names = [desc[0] for desc in curs.description]
            columns_str = ', '.join(column_names).replace('geom', 'ST_AsText(geom) AS geom')
            curs.execute(f"SELECT * FROM aws_s3.query_export_to_s3('SELECT {columns_str} FROM {schema}.{table}', aws_commons.create_s3_uri('{cache_bucket}','{s3_key}','us-east-1'), options :='format csv , HEADER true');")
            connection.commit()
    print(f"---> Wrote csv cache data from {schema}.{table} to {cache_bucket}/{s3_key}")
    return s3_key

###################################
# This function copies a publish data table within a db (or across databases using foreign data wrapper)
def publish_db_table(db, origin_table, dest_table, stage=True, add_oid=True, add_geom_index=True):
    
    if stage:
        dest_final_table = dest_table
        dest_final_table_name = dest_final_table.split(".")[1]
        dest_table = f"{dest_table}_stage"
    
    with db.get_db_connection() as db_connection:
        cur = db_connection.cursor()
        cur.execute(f"DROP TABLE IF EXISTS {dest_table};")
        cur.execute(f"SELECT * INTO {dest_table} FROM {origin_table};")
    
        if add_oid:
            print(f"---> Adding an OID to the {dest_table}")
            cur.execute(f'ALTER TABLE {dest_table} ADD COLUMN OID SERIAL PRIMARY KEY;')
        if add_geom_index:
            print(f"---> Adding an spatial index to the {dest_table}")
            cur.execute(f'CREATE INDEX ON {dest_table} USING GIST (geom);')  # Add a spatial index
        
        db_connection.commit()
        
        if stage:
            print(f"---> Renaming {dest_table} to {dest_final_table}")
            cur.execute(f'DROP TABLE IF EXISTS {dest_final_table};')  # Drop the published table if it exists
            cur.execute(f'ALTER TABLE {dest_table} RENAME TO {dest_final_table_name};')  # Rename the staged table
            db_connection.commit()
        
###################################
# This function drops and recreates a foreign data wrapper schema, so that table and column names are all up-to-date.     
def refresh_fdw_schema(db, local_schema, remote_server, remote_schema):
    with db.get_db_connection() as db_connection:
        cur = db_connection.cursor()
        sql = f"""
        DROP SCHEMA IF EXISTS {local_schema} CASCADE; 
        CREATE SCHEMA {local_schema};
        IMPORT FOREIGN SCHEMA {remote_schema} FROM SERVER {remote_server} INTO {local_schema};
        """
        cur.execute(sql)
        db_connection.commit()
    print(f"---> Refreshed {local_schema} foreign schema.")

###################################
# This function clears out old cache files outside of the buffer window
def cleanup_cache(bucket, table, reference_time, retention_days=30, buffer_days=3):
    s3_resource = boto3.resource('s3')

    # Determine the date threshold for keeping max flows files
    cuttoff_date = reference_time - timedelta(days=int(retention_days))
    buffer_hours = int(buffer_days*24)
    
    print(f"Clearing all cached versions of {table} older than {cuttoff_date}.")
    # Loop through a few days worth of buffer hours after the winodw to try to delete old files
    for hour in range(1, buffer_hours+1):
        buffer_datetime = cuttoff_date - timedelta(hours=hour)
        buffer_date = buffer_datetime.strftime("%Y%m%d")
        buffer_hour = buffer_datetime.strftime("%H%M")

        s3_key = f"viz_cache/{buffer_date}/{buffer_hour}/{table}.csv"

        old_file = s3_file(bucket, s3_key)
        if old_file.check_existence():
            s3_resource.Object(bucket, s3_key).delete()
            print(f"---> Deleted {s3_key} from {bucket}")