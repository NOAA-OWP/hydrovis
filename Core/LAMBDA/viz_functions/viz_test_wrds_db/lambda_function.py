from pathlib import Path
import re
import os

from viz_classes import database


THIS_DIR = Path(__file__).parent
FILES_DIR = THIS_DIR / 'files'
IGNORE_FILES = ['dba_stuff.sql']
IGNORE_TABLES = ['building_footprints_fema']

def lambda_handler(event, context):
    db = database(db_type='viz')
    connection = db.get_db_connection()

    wrds_db_host = os.getenv('WRDS_DB_HOST')
    wrds_db_username = os.getenv('WRDS_DB_USERNAME')
    wrds_db_password = os.getenv('WRDS_DB_PASSWORD')

    # SETUP FOREIGN SCHEMA POINTING TO wrds_location3_ondeck DB
    sql = f'''
        DROP SERVER IF EXISTS test_wrds_location CASCADE;
        DROP SCHEMA IF EXISTS automated_test CASCADE;
        DROP SCHEMA IF EXISTS test_external CASCADE;
        CREATE SCHEMA test_external;
        CREATE SCHEMA automated_test;
        CREATE SERVER test_wrds_location FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host '{wrds_db_host}', dbname 'wrds_location3_ondeck', port '5432');
        CREATE USER MAPPING FOR {wrds_db_username} SERVER test_wrds_location OPTIONS (user '{wrds_db_username}', password '{wrds_db_password}');
        IMPORT FOREIGN SCHEMA public FROM SERVER test_wrds_location INTO test_external;
        ALTER SERVER test_wrds_location OPTIONS (fetch_size '150000');
    '''
    
    db.execute_sql(connection, sql)
    
    for fname in FILES_DIR.iterdir():
        if fname.name in IGNORE_FILES: continue
        with open(fname, 'r', encoding="utf8") as f:
            sql = f.read()
            if 'external.' not in sql: continue
            
            external_table_matches = set(re.findall('external\.([A-Za-z0-9_-]+)', sql, flags=re.IGNORECASE))
            if len(external_table_matches) == 1 and list(external_table_matches)[0] in IGNORE_TABLES:
                print(f"Skipping {fname.name}...")
                continue

            print(f"Rewriting {fname.name} for test environment...")
            for table in external_table_matches:
                if table not in IGNORE_TABLES:
                    sql = re.sub(f'external.{table}', f'test_external.{table}', sql, flags=re.IGNORECASE)
            
            into_matches = re.findall('INTO ([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)', sql, flags=re.IGNORECASE)
            for into_match in into_matches:
                table = '.'.join(into_match)
                reference_matches = re.findall(f'(FROM|JOIN) {table}', sql, flags=re.IGNORECASE)
                into_replace = ''
                if reference_matches:
                    # This means an is created in the script and then subsequently used (i.e. an intermediate table)
                    # Thus, this line shouldn't be replaced, but the table written to should be changed to the 
                    # automated_test schema and the places where it is used (i.e. FROM <table>) should be updated
                    # to point to this automated_test schema as well
                    into_replace = f'INTO automated_test.{into_match[0]}_{into_match[1]}'
                    sql = re.sub(f'(FROM|JOIN) {table}\\b', f'\g<1> automated_test.{into_match[0]}_{into_match[1]}', sql, flags=re.IGNORECASE)
                sql = re.sub(f'INTO {table}\\b', into_replace, sql, flags=re.IGNORECASE)
                sql = re.sub(f'DROP TABLE IF EXISTS {table}\\b;?', '', sql, flags=re.IGNORECASE)

            print(f"Executing {fname.name} in test environment...")
            db.execute_sql(connection, sql)
    
    sql = f'''
        DROP SERVER IF EXISTS test_wrds_location CASCADE;
        DROP SCHEMA IF EXISTS automated_test CASCADE;
        DROP SCHEMA IF EXISTS test_external CASCADE;
    '''
    db.execute_sql(connection, sql)
    
    connection.close()
