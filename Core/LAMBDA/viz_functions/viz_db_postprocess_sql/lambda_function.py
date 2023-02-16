import re
from viz_classes import database

def lambda_handler(event, context):
    step = event['step']
    folder = event['folder']
    reference_time = event['args']['map']['reference_time']
    sql_replace = event['args']['sql_rename_dict']
    sql_replace.update({'1900-01-01 00:00:00': reference_time}) #setup a replace dictionary, starting with the reference time of the current pipeline.
    
    if step == "services":
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
        
        run_sql_file(sql_path, sql_replace)
   
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
            run_sql_file('admin/create_table_from_original.sql', sql_replace)
        run_sql_file('admin/ingest_prep.sql', sql_replace)

    if step == 'ingest_finish':
        sql_replace.update({"{files_imported}": 'NULL'}) #TODO Figure out how to get this from the last map of the state machine to here
        sql_replace.update({"{rows_imported}": 'NULL'}) #TODO Figure out how to get this from the last map of the state machine to here
        run_sql_file('admin/ingest_finish.sql', sql_replace)

# Run a sql file, and replace any items basd on the sql_replace dictionary.
def run_sql_file(sql_path, sql_replace):  
    # Find the sql file, and replace any items in the dictionary (at least has reference_time)
    sql = open(sql_path, 'r').read()
    for word, replacement in sql_replace.items():
        sql = re.sub(word, replacement, sql, flags=re.IGNORECASE).replace('utc', 'UTC')
    viz_db = database(db_type="viz")
    with viz_db.get_db_connection() as connection:
        cur = connection.cursor()
        cur.execute(sql)
        connection.commit()
    print(f"Finished running {sql_path}.")