import re
import os
from viz_classes import database

def lambda_handler(event, context):
    step = event['step']
    folder = event['folder']
    reference_time = event['args']['map']['reference_time']
    sql_replace = event['args']['sql_rename_dict']
    sql_replace.update({'1900-01-01 00:00:00': reference_time}) #setup a replace dictionary, starting with the reference time of the current pipeline.
    
    if step in ["services", "fim_config"]:
        if event['args']['map']['service']['configuration'] == "reference":
            return
    
    if folder == 'admin':
         run_admin_tasks(event, folder, step, sql_replace)
    else:
        # TODO: Clean up this conditional logic to be more readable.
        if step == 'summaries':
                sql_file = f"{event['args']['map']['map_item']}/{next(iter(event['args']['map_item']))}"
        elif 'map_item' in event['args']:
            sql_file = event['args']['map_item']
        else:
            sql_file = event['args']['map']['map_item']
        sql_path = f"{folder}/{sql_file}.sql"
        
        if step == 'max_flows' and max_flows_already_processed(sql_path, reference_time, sql_replace):
            return True
        
        run_sql(sql_path, sql_replace)
   
    return True

# Special function to handle admin-only sql tasks
def run_admin_tasks(event, folder, step, sql_replace):
    target_table = event['args']['map']['target_table']
    
    if not target_table:
        return
    
    original_table = event['args']['map']['original_table']
    index_columns = event['args']['map']['index_columns']
    index_name = event['args']['map']['index_name']
    schema = target_table.split('.')[0]
    target_table_only = target_table.split('.')[-1]
    
    sql_replace.update({"{target_table}": target_table})
    sql_replace.update({"{target_table_only}": target_table_only})
    sql_replace.update({"{target_schema}": schema})
    sql_replace.update({"{index_name}": index_name})
    sql_replace.update({"{index_columns}": index_columns})
    
    if step == 'ingest_prep':
        # if target table is not the original table, run the create command to create the table
        if target_table != original_table:
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
    # Determine if arg is file or raw SQL string
    if os.path.exists(sql_path_or_str):
        sql = open(sql_path_or_str, 'r').read()
    else:
        sql = sql_path_or_str
    if sql_replace:
        # replace portions of SQL with any items in the dictionary (at least has reference_time)
        for word, replacement in sql_replace.items():
            sql = re.sub(word, replacement, sql, flags=re.IGNORECASE).replace('utc', 'UTC')
    viz_db = database(db_type="viz")
    with viz_db.get_db_connection() as connection:
        cur = connection.cursor()
        print(sql)
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
    result = run_sql(sql)
    
    if not result:
        return False
        
    if result[0] == reference_time:
        print(f"NOTE: {sql_path} was already executed for reference time {reference_time}")
        return True
    else:
        return False
