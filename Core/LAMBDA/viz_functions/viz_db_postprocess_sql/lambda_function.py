import re
import os
from datetime import datetime
from viz_classes import database

def lambda_handler(event, context):
    step = event['step']
    folder = event['folder']
    reference_time = event['args']['reference_time']
    reference_date = datetime.strptime(reference_time, "%Y-%m-%d %H:%M:%S")
    ref_time_short = reference_date.strftime("%Y%m%dT%H%M")
    sql_replace = event['args']['sql_rename_dict']
    sql_replace.update({'1900-01-01 00:00:00': reference_time}) #setup a replace dictionary, starting with the reference time of the current pipeline.
    
    # Don't run any SQL if it's a reference service
    if step in ["products", "fim_config"]:
        if event['args']['product']['configuration'] == "reference":
            return
        
    if 'fim_config' in event['args']:
        sql_replace.update({"{rs_fim_table}":f"fim.{event['args']['fim_config']['postprocess']['sql_file']}"})
        sql_replace.update({"{rs_streamflow_table}":f"fim.{event['args']['fim_config']['postprocess']['sql_file']}_status"})
        sql_replace.update({"{db_fim_table}":f"ingest.{event['args']['fim_config']['postprocess']['sql_file']}"})
        sql_replace.update({"{db_streamflow_table}":f"ingest.{event['args']['fim_config']['postprocess']['sql_file']}_flows"})
    
    ###### Conditional Logic #####
    # TODO: I'm wondering if it makes sense to move all this conditional logic to initialize_pipeline, so that this function can remain more abstract
    # Admin tasks
    if folder == 'admin':
         db_type = "viz"
         run_admin_tasks(event, folder, step, sql_replace, reference_time)
    else:
        sql_files = {}
        # Max Flow
        if step == "max_flows":
            db_type = "viz"
            sql_file = event['args']['db_max_flow']['max_flows_sql_file']
            sql_files.update({sql_file: db_type})
        
        ############# FIM Processing ###############
        # FIM Data Prep - Flows to Redshift
        elif step == 'copy_flows_to_redshift':
            db_type = 'viz'
            sql_file = '1a_rds_build_inundation_flows_table'
            sql_files.update({sql_file: db_type})
            db_type = 'redshift'
            sql_file = '1b_redshift_copy_inundation_flows'
            sql_files.update({sql_file: db_type})
        # FIM Data Prep - Query cached FIM table on Redshift
        elif step == 'query_cached_fim_table_on_redshift':
            db_type = 'redshift'
            sql_file = '2_redshift_query_cached_fim_table'
            sql_files.update({sql_file: db_type})
        # FIM Caching - Add processed FIM to Redshift cache
        elif step == 'add_processed_fim_to_redshift':
            #Step a - Create temporary view on RDS to split up the geometries for import to Redshift
            sql_replace.update({"{db_fim_temp_geo_view}":f"ingest.{event['args']['fim_config']['postprocess']['sql_file']}_{ref_time_short}"})
            db_type = 'viz'
            sql_file = '3a_rds_create_temp_fim_geo_view'
            sql_files.update({sql_file: db_type})
            #Step b - Using the new view, cache generated FIM to the Redshift db
            sql_replace.update({"{postgis_fim_table}":f"external_viz_ingest.{event['args']['fim_config']['postprocess']['sql_file']}"})
            sql_replace.update({"{postgis_fim_temp_geo_view}":f"external_viz_ingest.{event['args']['fim_config']['postprocess']['sql_file']}_{ref_time_short}"})
            db_type = 'redshift'
            sql_file = '3b_redshift_cache_fim_from_rds'
            sql_files.update({sql_file: db_type})
            #Steb c - Drop the temporary view
            db_type = 'viz'
            sql_file = '3a_rds_create_temp_fim_geo_view'
            sql_files.update({sql_file: db_type})
        # FIM Config
        elif step == 'fim_config':
            if not event['args']['fim_config'].get('postprocess'):
                return
            db_type = "viz"
            sql_file = event['args']['fim_config']['postprocess']['sql_file']
            sql_files.update({sql_file: db_type})
        ###########################################
        
        # Product
        elif step == "products":
            db_type = "viz"
            folder = os.path.join(folder, event['args']['product']['configuration'])
            sql_file = event['args']['postprocess_sql']['sql_file']
            sql_files.update({sql_file: db_type})
        # Summary
        elif step == 'summaries':
            db_type = "viz"
            folder = os.path.join(folder, event['args']['product']['product'])
            sql_file = event['args']['postprocess_summary']['sql_file']
            sql_files.update({sql_file: db_type})
        
            
        # Iterate through the sql commands defined in the logic above
        for sql_file, db_type in sql_files.items():

            ### Run the Appropriate SQL File ###
            sql_path = f"{folder}/{sql_file}.sql"
            
            #TODO - not sure if we should update this for redshift steps or not
            if db_type == "viz" and "redshift" not in step:
                # Checks if all tables references in sql file exist and are updated (if applicable)
                # Raises a custom RequiredTableNotUpdated if not, which will be caught by viz_pipline
                # and invoke a retry
                database(db_type=db_type).check_required_tables_updated(sql_path, sql_replace, reference_time, raise_if_false=True)

            run_sql(sql_path, sql_replace, db_type=db_type)
   
    return True

# Special function to handle admin-only sql tasks
def run_admin_tasks(event, folder, step, sql_replace, reference_time):
    past_event = True if len(sql_replace) > 1 else False
    target_table = event['args']['db_ingest_group']['target_table']
    index_columns = event['args']['db_ingest_group']['index_columns']
    index_name = event['args']['db_ingest_group']['index_name']
    dependent_on = event['args']['db_ingest_group']['dependent_on']
    target_schema = target_table.split('.')[0]
    target_table_only = target_table.split('.')[-1]
    
    sql_replace.update({"{target_table}": target_table})
    sql_replace.update({"{target_table_only}": target_table_only})
    sql_replace.update({"{target_schema}": target_schema})
    sql_replace.update({"{index_name}": index_name})
    sql_replace.update({"{index_columns}": index_columns})
    
    # This will effectively pause an ingest group / pipeline if a dependent_on key is present - currently used to have MRF NBM run after MRF GFS
    if dependent_on != "":
        database(db_type="viz").check_required_tables_updated(f"SELECT * FROM {dependent_on} LIMIT 1", sql_replace, reference_time, raise_if_false=True)
    
    if step == 'ingest_prep':
        # if target table is not the original table, run the create command to create the table
        if past_event is True:
            original_table = [k for k, v in sql_replace.items() if v == target_table and k != ''][0]
            sql_replace.update({"{original_table}": original_table})
            run_sql('admin/create_table_from_original.sql', sql_replace)
            
        run_sql('admin/ingest_prep.sql', sql_replace)

    if step == 'ingest_finish':
        sql_replace.update({"{files_imported}": 'NULL'}) #TODO Figure out how to get this from the last map of the state machine to here
        sql_replace.update({"{rows_imported}": 'NULL'}) #TODO Figure out how to get this from the last map of the state machine to here
        
        feature_id_column_exists = run_sql('admin/ingest_finish.sql', sql_replace)
        if feature_id_column_exists[0]:
            run_sql('admin/remove_oconus_features.sql', sql_replace)
        
# Run sql from string or file, and replace any items basd on the sql_replace dictionary.
def run_sql(sql_path_or_str, sql_replace=None, db_type="viz"):
    result = None
    if not sql_replace:
        sql_replace = {}
        
    # Determine if arg is file or raw SQL string
    if os.path.exists(sql_path_or_str):
        sql = open(sql_path_or_str, 'r').read()
        print(f" Executing {sql_path_or_str}")
    else:
        sql = sql_path_or_str
        print(f" Executing custom sql")

    # replace portions of SQL with any items in the dictionary (at least has reference_time)
    # sort the replace dictionary to have longer values upfront first
    sql_replace = sorted(sql_replace.items(), key = lambda item : len(item[1]), reverse = True)
    for word, replacement in sql_replace:
        sql = re.sub(re.escape(word), replacement, sql, flags=re.IGNORECASE).replace('utc', 'UTC')

    db = database(db_type=db_type)
    with db.get_db_connection() as connection:
        cur = connection.cursor()
        cur.execute(sql)
        try:
            result = cur.fetchone()
        except:
            pass
        connection.commit()
    connection.close()
    print(f"---> Finished.")
    return result
