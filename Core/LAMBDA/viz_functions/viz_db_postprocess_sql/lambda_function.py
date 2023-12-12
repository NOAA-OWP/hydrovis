import re
import os
from datetime import datetime
from viz_classes import database

def lambda_handler(event, context):
    step = event['step']
    folder = event['folder']
    reference_time = event['args']['reference_time']
    sql_replace = event['args']['sql_rename_dict']
    sql_replace.update({'1900-01-01 00:00:00': reference_time}) #setup a replace dictionary, starting with the reference time of the current pipeline.
    check_dependencies = True #default value, unless specified elsewhere
    
    # Don't run any SQL if it's a reference service
    if step in ["products", "fim_config"]:
        if event['args']['product']['configuration'] == "reference":
            return
        
    # For FIM steps, setup some other variables based on the step function inputs and provide them to the sql_replace dictionary as args/params
    if step == "hand_pre_processing" or step == "hand_post_processing" or step == "fim_config":
        # Define the table names that will be used in the SQL templates
        # TODO: Move this to initialize pipeline and Update this to work with past event functionality
        max_flows_table = event['args']['fim_config']['flows_table']
        db_fim_table = event['args']['fim_config']['target_table']
        rs_fim_table = db_fim_table.replace("ingest", "ingest_rs")
        domain = event['args']['product']['domain']
        sql_replace.update({"{max_flows_table}":max_flows_table})
        sql_replace.update({"{db_fim_table}":db_fim_table})
        sql_replace.update({"{rs_fim_table}":rs_fim_table})
        sql_replace.update({"{domain}":domain})
        sql_replace.update({"{postgis_fim_table}":db_fim_table.replace("ingest", "external_viz_ingest")})
        sql_replace.update({"{db_publish_table}":db_fim_table.replace("ingest", "publish")})

    ############################################################ Conditional Logic ##########################################################
    # This section contains the conditional logic of database operations within our pipelline. At some point it may be nice to abstract this.
    
    # General RDS DB Admin tasks
    if folder == 'admin':
         db_type = "viz"
         run_admin_tasks(event, folder, step, sql_replace, reference_time)
    else:
        sql_files_to_run =[]
        # Max Flow
        if step == "max_flows":
            db_type = "viz"
            sql_file = event['args']['db_max_flow']['max_flows_sql_file']
            sql_files_to_run.append({"sql_file":sql_file, "db_type":db_type})
        
        ############################################# FIM Processing ##############################################  
        # The following database operations are taken below to process FIM, mostly based on the input parameters defined in the step function as a dictonary of sql files to execute, with a sql_file key and db_type value.
        # 0. Create four tables, if they don't already exist, on both RDS and Redshift. These tables replicate the schema of the HAND cache, and are truncated and re-populated as part of each FIM run:
        #       - ingest.{fim_config}_flows                 - this is a version of max_flows, with fim crosswalk columns added, as well as filtering for hight water threshold
        #       - ingest.{fim_config}                       - this is the fim table, but without geometry
        #       - ingest.{fim_config}_geo                   - this is the geometries for the fim table (one-to-many, since we're subdividing to keep geometries small for Redshift)
        #       - ingest.{fim_config}_zero_stage            - this table holds all of the fim features (hydro_table, feature_id, huc8, branch combinations) that have zero or NaN stage at the current discharge value
        #       - ingest.{fim_config}_geo_view (RDS only)   - this view subdivides the newly polygons in the inundation_geo table (because Redshift has a limit on the size of geometries)
        #       - publish.{fim_config} (RDS only)           - This is the finished publish table that gets copied to the EGIS service
        # 1. Populate the FIM flows table on RDS (from max_flows with some joins), then copy it to Redshift
        # 2. Query the HAND Cache on Redshift
        #       a. Query the HAND cache on Redshift, joining to the just-populated flows table, to populate the just truncated inundation, inundation_geo, and inundation_zero_stage tables on Redshift
        # 3. Populate the inundation tables on RDS
        #       a. Prioritize Ras2FIM by querying the Ras2FIM cache on RDS first #TODO
        #       b. Copy the FIM tables on Redshift (which were just populated from the HAND cache in 2a) into the inundation tables on RDS (skipping any records that were already added from Ras2FIM)
        #       a. HAND processing for any FIM features remaining in the inundation flows table, that have not been added to the inundation table from Ras2FIM or the HAND cache (not done here, but administered by the fim_data_prep lambda function
        # 4. Generate publish.inundation table on RDS, and copy it to the EGIS (done via the update_egis_data function)
        #       a. We can use a template to do this generically for most inland inundation configurations (e.g. NWM)
        # 5. Add any newly generated HAND features in this run into the Redshift HAND cache ( #TODO: it would be good to figure out how to do this in parallel outside of the fim_config map, so that this doesn't hold things up).
        #       a. Insert records from the RDS inundation, inundation_geo, and inundation_zero_stage tables/view into the Redshift HAND cache tables, only taking records generated by HAND Processing, and which the primary key does not already exist (hydro_id, feature_id, huc8, branch, rc_stage_ft)
        
        # All of the pre and post processing steps (everything but step 4) are templated, and can be executed using the input parameters defined in the step function
        elif step == "hand_pre_processing" or step == "hand_post_processing":     
            # Get the sql file instructions from the step function parameter dictionary, and add it to the list to run
            sql_templates_to_run = event['sql_templates_to_run']
            sql_files_to_run.extend(sql_templates_to_run)
            
        # Step 4 - FIM Config - This is where we actually create the publish inundation tables to send to the EGIS service, and in this case we look to
        # see if a product-specific sql file exists (for special cases like RnR), and if not, we run the template file.
        elif step == 'fim_config':
            if not event['args']['fim_config'].get('postprocess'):
                return
            db_type = "viz"
            sql_file = event['args']['fim_config']['postprocess']['sql_file']
            if os.path.exists(os.path.join(folder, sql_file)): #if there is product-specific fim_configs sql file, use it.
                sql_files_to_run.append({"sql_file":sql_file, "db_type":db_type})
            else: # if not, use the fim_publish_template
                folder = 'fim_caching_templates'
                sql_file = '4a_rds_create_fim_publish_table'
                sql_replace.update({"{domain}":domain})
                sql_files_to_run.append({"sql_file":sql_file, "db_type":db_type})
        ###########################################
        
        # Product
        elif step == "products":
            db_type = "viz"
            folder = os.path.join(folder, event['args']['product']['configuration'])
            sql_file = event['args']['postprocess_sql']['sql_file']
            sql_files_to_run.append({"sql_file":sql_file, "db_type":db_type})
        # Summary
        elif step == 'summaries':
            db_type = "viz"
            folder = os.path.join(folder, event['args']['product']['product'])
            sql_file = event['args']['postprocess_summary']['sql_file']
            sql_files_to_run.append({"sql_file":sql_file, "db_type":db_type})

    ############################################################ Run the SQL ##########################################################
        # Iterate through the sql commands defined in the logic above
        for sql_file_to_run in sql_files_to_run:
            sql_file = sql_file_to_run['sql_file']
            db_type = sql_file_to_run['db_type']
            if 'check_dependencies' in sql_file_to_run:
                check_dependencies = sql_file_to_run['check_dependencies']
            
            ### Get the Appropriate SQL File ###
            sql_path = f"{folder}/{sql_file}.sql"
            
            if db_type == "viz" and check_dependencies is True:
                # Checks if all tables references in sql file exist and are updated (if applicable)
                # Raises a custom RequiredTableNotUpdated if not, which will be caught by viz_pipline
                # and invoke a retry
                # TODO: I do not currently have this setup for Redshift, need to think that through.
                database(db_type=db_type).check_required_tables_updated(sql_path, sql_replace, reference_time, raise_if_false=True)

            run_sql(sql_path, sql_replace, db_type=db_type)
   
    return True

############################################################################################################################################
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
