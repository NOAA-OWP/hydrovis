import re
import os
from datetime import datetime
from viz_classes import database

FIM_VERSION = os.environ['FIM_VERSION']
HAND_VERSION = os.environ['HAND_VERSION']
RAS2FIM_VERSION = os.environ['RAS2FIM_VERSION']

def lambda_handler(event, context):
    step = event['step']
    folder = event['folder']
    reference_time = event['args']['reference_time']
    sql_replace = event['args']['sql_rename_dict']
    sql_replace.update({'1900-01-01 00:00:00': reference_time}) #setup a replace dictionary, starting with the reference time of the current pipeline.
    check_dependencies = True #default value, unless specified elsewhere
    
    # Don't run any SQL if it's a reference service for select steps
    if step in ["products", "fim_config", "hand_pre_processing", "hand_post_processing", "hand_pre_processing - prepare flows"]:
        if event['args']['product']['configuration'] == "reference":
            return
        
    # For FIM steps that require template use, setup some other variables based on the step function inputs and provide them to the sql_replace dictionary as args/params
    # TODO: This is probably better to move to initialize pipeline and/or abstract these conditions / have the steps that need this specify it in the initilize_pipeline config files
    if "hand_pre_processing" in step or step == "hand_post_processing" or step == "fim_config":
        if event['args']['fim_config']['fim_type'] == 'hand':
            
            # Define the table names that will be used in the SQL templates
            max_flows_table = event['args']['fim_config']['flows_table']
            db_fim_table = event['args']['fim_config']['target_table']
            domain = event['args']['product']['domain']
            db_publish_table = db_fim_table.replace("fim_ingest", "publish")
            
            # If these tables exist in the sql_replace dictionary, update accordingly (for past events)
            if max_flows_table in sql_replace:
                max_flows_table = sql_replace[max_flows_table]
            if db_fim_table in sql_replace:
                db_fim_table = sql_replace[db_fim_table]
            if db_publish_table in sql_replace:
                db_publish_table = sql_replace[db_publish_table]            
            
            sql_replace.update({"{max_flows_table}": max_flows_table})
            sql_replace.update({"{db_fim_table}": db_fim_table})
            sql_replace.update({"{domain}": domain})
            sql_replace.update({"{db_publish_table}": db_publish_table})
            sql_replace.update({"{fim_version}": FIM_VERSION}) 
            sql_replace.update({"{hand_version}": HAND_VERSION}) 
            sql_replace.update({"{ras2fim_version}": RAS2FIM_VERSION}) 

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
            sql_files_to_run.append({"sql_file":sql_file, "folder": folder, "db_type":db_type})  
        
        ###################### FIM Workflows ######################
        # All of the pre and post processing steps of a fim workflow (everything but step 4) - see attached readme - are templated, and can be executed using the input parameters defined in the step function
        elif step == "hand_pre_processing" or step == "hand_post_processing":     
            # Get the sql file instructions from the step function parameter dictionary, and add it to the list to run
            sql_templates_to_run = event['sql_templates_to_run']
            sql_files_to_run.extend(sql_templates_to_run)

        elif step == "hand_pre_processing - prepare flows":
            # If a sql file is present for this fim_config in the fim_flows folder, use it to generate flows table instead of the template.
            fim_flows_file = os.path.join("fim_flows", event['args']['fim_config']['name'] + '.sql')
            if os.path.exists(fim_flows_file):
                sql_file = event['args']['fim_config']['name']
                sql_files_to_run.append({"sql_file":sql_file, "folder": "fim_flows", "db_type":"viz"})

                # If a flows column is present in the fim_config, add that to the sql replace dictionary.
                if 'flows_column' in event['args']['fim_config']:
                    sql_replace.update({"{flows_column}": event['args']['fim_config']['flows_column']})
            else:
                sql_templates_to_run = event['sql_templates_to_run']
                sql_files_to_run.extend(sql_templates_to_run) 
            
        # FIM Config Step 4 - This is where we actually create the publish inundation tables to send to the EGIS service, and in this case we look to
        # see if a product-specific sql file exists (for special cases like RnR, CatFIM, etc.), and if not, we use a template file.
        elif step == 'fim_config':
            if not event['args']['fim_config'].get('postprocess'):
                return
            db_type = "viz"
            sql_file = event['args']['fim_config']['postprocess']['sql_file']
            if os.path.exists(os.path.join("fim_configs", sql_file + '.sql')): #if there is product-specific fim_configs sql file, use it.
                sql_files_to_run.append({"sql_file":sql_file, "folder": "fim_configs", "db_type":db_type})  
            else: # if not, use the fim_publish_template
                sql_templates_to_run = event['sql_templates_to_run']
                sql_files_to_run.extend(sql_templates_to_run) 
        
        ##########################################################
        
        # Product
        elif step == "products":
            db_type = "viz"
            folder = os.path.join(folder, event['args']['product']['configuration'])
            sql_file = event['args']['postprocess_sql']['sql_file']
            sql_files_to_run.append({"sql_file":sql_file, "folder": folder, "db_type":db_type})  
        # Summary
        elif step == 'summaries':
            db_type = "viz"
            folder = os.path.join(folder, event['args']['product']['product'])
            sql_file = event['args']['postprocess_summary']['sql_file']        
            sql_files_to_run.append({"sql_file":sql_file, "folder": folder, "db_type":db_type})  

    ############################################################ Run the SQL ##########################################################
        # Iterate through the sql commands defined in the logic above
        for sql_file_to_run in sql_files_to_run:
            sql_file = sql_file_to_run['sql_file']
            folder = sql_file_to_run['folder']
            db_type = sql_file_to_run['db_type']
            if 'check_dependencies' in sql_file_to_run: # This allows one to set a specific step to not check db dependences, which we currently want to avoid on Redshift and Hand Preprocessing steps (since tables are truncated prior)
                check_dependencies = sql_file_to_run['check_dependencies']
            
            ### Get the Appropriate SQL File ###
            sql_path = f"{folder}/{sql_file}.sql"
            
            if db_type == "viz" and check_dependencies is True:
                # Checks if all tables references in sql file exist and are updated (if applicable)
                # Raises a custom RequiredTableNotUpdated if not, which will be caught by viz_pipline
                # and invoke a retry
                # TODO: This doesn't work great with the new FIM_Caching templates, so I'm presently skipping it on several of the FIM steps.'
                # I'll try to re-work this if there is time, but we need a way to ignore certain types of this error when appropriate, such as no fim records in HI, which happens often.
                database(db_type=db_type).check_required_tables_updated(sql_path, sql_replace, reference_time, raise_if_false=True)

            run_sql(sql_path, sql_replace, db_type=db_type)
   
    return True

############################################################################################################################################
# Special function to handle admin-only sql tasks - this is used for preparing for and finishing ingest tasks
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
        
############################################################################################################################################
# This function runs SQL on a database. It also can accept a sql_replace dictionary, where it does a find and replace on the SQL text before execution.
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
    connection = db.get_db_connection()
    with connection:
        with connection.cursor() as cur:
            cur.execute(sql)
            try:
                result = cur.fetchone()
            except:
                pass
    connection.close()
    print(f"---> Finished.")
    return result
