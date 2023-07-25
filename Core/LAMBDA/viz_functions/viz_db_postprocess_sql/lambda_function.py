import re
import os
from viz_classes import database

def lambda_handler(event, context):
    step = event['step']
    folder = event['folder']
    reference_time = event['args']['reference_time']
    sql_replace = event['args']['sql_rename_dict']
    sql_replace.update({'1900-01-01 00:00:00': reference_time}) #setup a replace dictionary, starting with the reference time of the current pipeline.
    
    # Don't run any SQL if it's a reference service
    if step in ["products", "fim_config"]:
        if event['args']['product']['configuration'] == "reference":
            return
        
    # Admin tasks
    if folder == 'admin':
         run_admin_tasks(event, folder, step, sql_replace)
    else:
        # Max Flow
        if step == "max_flows":
            sql_file = event['args']['db_max_flow']['max_flows_sql_file']
        # FIM Config
        elif step == 'fim_config':
            if not event['args']['fim_config'].get('postprocess'):
                return
            sql_file = event['args']['fim_config']['postprocess']['sql_file']
        # Product
        elif step == "products":
            folder = os.path.join(folder, event['args']['product']['configuration'])
            sql_file = event['args']['postprocess_sql']['sql_file']
        # Summary
        elif step == 'summaries':
            folder = os.path.join(folder, event['args']['product']['product'])
            sql_file = event['args']['postprocess_summary']['sql_file'] 
        
        ### Run the Appropriate SQL File ###
        sql_path = f"{folder}/{sql_file}.sql"
        
        # Checks if all tables references in sql file exist and are updated (if applicable)
        # Raises a custom RequiredTableNotUpdated if not, which will be caught by viz_pipline
        # and invoke a retry
        database(db_type="viz").check_required_tables_updated(sql_path, sql_replace, reference_time, raise_if_false=True)

        run_sql(sql_path, sql_replace)
   
    return True

# Special function to handle admin-only sql tasks
def run_admin_tasks(event, folder, step, sql_replace):
    past_event = True if len(sql_replace) > 1 else False
    target_table = event['args']['db_ingest_group']['target_table']
    index_columns = event['args']['db_ingest_group']['index_columns']
    index_name = event['args']['db_ingest_group']['index_name']
    target_schema = target_table.split('.')[0]
    target_table_only = target_table.split('.')[-1]
    
    sql_replace.update({"{target_table}": target_table})
    sql_replace.update({"{target_table_only}": target_table_only})
    sql_replace.update({"{target_schema}": target_schema})
    sql_replace.update({"{index_name}": index_name})
    sql_replace.update({"{index_columns}": index_columns})

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
        run_sql('admin/ingest_finish.sql', sql_replace)
        
# Run sql from string or file, and replace any items basd on the sql_replace dictionary.
def run_sql(sql_path_or_str, sql_replace=None):
    result = None
    if not sql_replace:
        sql_replace = {}
        
    # Determine if arg is file or raw SQL string
    if os.path.exists(sql_path_or_str):
        sql = open(sql_path_or_str, 'r').read()
    else:
        sql = sql_path_or_str

    # replace portions of SQL with any items in the dictionary (at least has reference_time)
    # sort the replace dictionary to have longer values upfront first
    sql_replace = sorted(sql_replace.items(), key = lambda item : len(item[1]), reverse = True)
    for word, replacement in sql_replace:
        sql = re.sub(re.escape(word), replacement, sql, flags=re.IGNORECASE).replace('utc', 'UTC')
        
    viz_db = database(db_type="viz")
    with viz_db.get_db_connection() as connection:
        cur = connection.cursor()
        cur.execute(sql)
        try:
            result = cur.fetchone()
        except:
            pass
        connection.commit()
    print(f"Finished executing the SQL statement above.")
    return result
