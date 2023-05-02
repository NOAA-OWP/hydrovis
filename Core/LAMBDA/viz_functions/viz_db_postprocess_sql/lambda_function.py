import re
import os
from viz_classes import database

class RequiredTableNotUpdated(Exception):
    """ This is a custom exception to report back to the AWS Step Function that a required table (dependent_on_table) has not yet been updated with the current reference time. """

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
            if max_flows_already_processed(f"{folder}/{sql_file}.sql", reference_time, sql_replace):
                return True
        # FIM Config
        elif step == 'fim_config':
            if not event['args']['fim_config'].get('postprocess'):
                return
            sql_file = event['args']['fim_config']['postprocess']['sql_file']
        # Product
        elif step == "products":
            folder = os.path.join(folder, event['args']['product']['configuration'])
            sql_file = event['args']['postprocess_sql']['sql_file']
            if event.get('args').get('postprocess_sql').get('dependent_on_db_tables'):
                dependent_on_tables = event['args']['postprocess_sql']['dependent_on_db_tables']
                if len(dependent_on_tables) > 0:
                    print("Dependent DB Table Specified - Checking if complete.")
                    if check_required_tables(dependent_on_tables, reference_time) is False:
                        print("Reference Time not yet present in required table. Pausing and Retrying.")
                        raise RequiredTableNotUpdated
        # Summary
        elif step == 'summaries':
            folder = os.path.join(folder, event['args']['product']['product'])
            sql_file = event['args']['postprocess_summary']['sql_file'] 
        
        ### Run the Appropriate SQL File ###
        sql_path = f"{folder}/{sql_file}.sql"
        run_sql(sql_path, sql_replace)
   
    return True

# Special function to handle admin-only sql tasks
def run_admin_tasks(event, folder, step, sql_replace):
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
    for word, replacement in sql_replace.items():
        sql = re.sub(word, replacement, sql, flags=re.IGNORECASE).replace('utc', 'UTC')
        
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

def max_flows_already_processed(sql_path, reference_time, sql_replace):
    sql = open(sql_path, 'r').read().lower()
    for word, replacement in sql_replace.items():
        sql = re.sub(word, replacement, sql, flags=re.IGNORECASE).replace('utc', 'UTC')
    schema, table = re.search('into (\w+)\.(\w+)', sql).groups()
    sql = f'SELECT reference_time FROM {schema}.{table} LIMIT 1;'
    try:
        result = run_sql(sql)
    except:
        return False
    
    if not result:
        return False
        
    if result[0] == reference_time:
        print(f"NOTE: {sql_path} was already executed for reference time {reference_time}")
        return True
    else:
        return False
    
def check_required_tables(dependent_on_tables, reference_time):
    for table in dependent_on_tables:
        result = run_sql(f"SELECT reference_time FROM {table} LIMIT 1")
        if not result:
            return False
        elif result[0].replace(" UTC", "") == reference_time:
            return True
        else:
            return False