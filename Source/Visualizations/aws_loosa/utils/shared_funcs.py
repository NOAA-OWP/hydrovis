import arcpy
import datetime
import json
import pandas as pd
import geopandas as gpd
import numpy as np
from sqlalchemy import create_engine
import psycopg2
import psycopg2.extras
import os
import shutil
import boto3
import tempfile

from aws_loosa.consts.paths import PROCESSED_OUTPUT_BUCKET, PROCESSED_OUTPUT_PREFIX
arcpy.env.overwriteOutput = True


def add_update_time(data, method='extend_table'):
    print("Updating/Adding Update Time")

    if method not in ['extend_table', 'calculate_field', 'array']:
        raise Exception("method must be extend_table, calculate_field,  or array")

    update_time = datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%d %H:%M UTC")

    if method == 'extend_table':
        print("--> Updating table by extending existing attributes")

        # Try to get only a single column to restrict unnecessary loading and memory usage
        try:
            arr = arcpy.da.FeatureClassTonpArray(data, ('OBJECTID'))
        except RuntimeError:  # Runtime error is raised when a column does not exist
            try:
                arr = arcpy.da.FeatureClassTonpArray(data, ('OBJECTID_1'))
            except RuntimeError:
                arr = arcpy.da.FeatureClassTonpArray(data, ('*'))

        object_dtype = [arr.dtype.descr[0]]
        object_name = arr.dtype.descr[0][0]

        new_dt = np.dtype(object_dtype + [('update_time', '<U42')])
        new_data = np.zeros((len(arr)), dtype=new_dt)
        new_data[object_name] = arr[object_name]
        new_data['update_time'] = update_time
        arcpy.da.ExtendTable(data, object_name, new_data, object_name)
    elif method == 'calculate_field':
        print("--> Updating table by calculating field")
        fields = [field.name for field in arcpy.ListFields(data)]

        if 'update_time' not in fields:
            arcpy.AddField_management(data, "update_time", "TEXT", field_alias='Update Time')
            arcpy.AddIndex_management(data, ["update_time"], "update_time_Index", "NON_UNIQUE", "NON_ASCENDING")

        arcpy.CalculateField_management(data, "update_time", f"'{update_time}'", "PYTHON3")
    elif method == 'array':
        print("--> Updating table by extending np array")
        new_dt = np.dtype(data.dtype.descr + [('update_time', '<U42')])
        new_data = np.zeros(data.shape, dtype=new_dt)
        for i in data.dtype.names:
            new_data[i] = data[i]
        new_data['update_time'] = update_time

        data = new_data

    return data


def add_ref_time(data, ref_time, field_name='Ref_Time', method='extend_table'):
    print("Updating/Adding Reference Time")
    ref_time = ref_time.strftime("%Y-%m-%d %H:%M UTC")

    if field_name == "Ref_Time":
        field_alias = "Reference Time"
    elif field_name == "Valid_Time":
        field_alias = "Valid Time"
    else:
        field_alias = field_name.replace("_", " ")

    if method == 'extend_table':
        print("--> Updating table by extending existing attributes")
        arr = arcpy.da.FeatureClassTonpArray(data, ('*'))
        object_dtype = [arr.dtype.descr[0]]
        object_name = arr.dtype.descr[0][0]

        new_dt = np.dtype(object_dtype + [(field_name, '<U42')])
        new_data = np.zeros((len(arr)), dtype=new_dt)
        new_data[object_name] = arr[object_name]
        new_data[field_name] = ref_time
        arcpy.da.ExtendTable(data, object_name, new_data, object_name)
    elif method == 'calculate_field':
        print("--> Updating table by calculating field")
        fields = [field.name for field in arcpy.ListFields(data)]

        if field_name not in fields:
            arcpy.AddField_management(data, field_name, "TEXT", field_alias=field_alias)
            arcpy.AddIndex_management(data, [field_name], f"{field_name}_Index", "NON_UNIQUE", "NON_ASCENDING")

        arcpy.CalculateField_management(data, field_name, f"'{ref_time}'", "PYTHON3")
    elif method == 'array':
        print("--> Updating table by extending np array")
        new_dt = np.dtype(data.dtype.descr + [(field_name, '<U42')])
        new_data = np.zeros(data.shape, dtype=new_dt)
        for i in data.dtype.names:
            new_data[i] = data[i]
        new_data[field_name] = ref_time

        data = new_data

    return data


def update_field_name(feature_class, new_name_dict):
    print("Updating Name Field")

    expression = "get_new_name(!Name!)"
    str_dict = json.dumps(new_name_dict)
    code_block = f"""def get_new_name(name):
    new_name_dict={str_dict}
    return new_name_dict[name]"""

    arcpy.CalculateField_management(feature_class, 'Name', expression, "PYTHON3", code_block)


def get_db_engine(db_type):
    if db_type == "viz":
        print("Getting environment variables for access to the viz DB")
        db_host = os.environ['VIZ_DB_HOST']
        db_name = os.environ['VIZ_DB_DATABASE']
        db_user = os.environ['VIZ_DB_USERNAME']
        db_password = os.environ['VIZ_DB_PASSWORD']
    elif db_type == "egis":
        print("Getting environment variables for access to the egis DB")
        db_host = os.environ['EGIS_DB_HOST']
        db_name = os.environ['EGIS_DB_DATABASE']
        db_user = os.environ['EGIS_DB_USERNAME']
        db_password = os.environ['EGIS_DB_PASSWORD']
    else:
        raise Exception("db_type must be viz or egis")

    print("Creating the viz DB engine")
    db_engine = create_engine(f'postgresql://{db_user}:{db_password}@{db_host}/{db_name}')

    return db_engine


def get_db_connection(db_type):
    if db_type == "viz":
        print("Getting environment variables for access to the viz DB")
        db_host = os.environ['VIZ_DB_HOST']
        db_name = os.environ['VIZ_DB_DATABASE']
        db_user = os.environ['VIZ_DB_USERNAME']
        db_password = os.environ['VIZ_DB_PASSWORD']
    elif db_type == "egis":
        print("Getting environment variables for access to the egis DB")
        db_host = os.environ['EGIS_DB_HOST']
        db_name = os.environ['EGIS_DB_DATABASE']
        db_user = os.environ['EGIS_DB_USERNAME']
        db_password = os.environ['EGIS_DB_PASSWORD']
    else:
        raise Exception("db_type must be viz or egis")

    print(f"Creating the {db_type} DB engine")
    connection = psycopg2.connect(f"host={db_host} dbname={db_name} user={db_user} password={db_password}")

    return connection


def get_db_values(table, columns, db_type="viz"):
    print("Connecting to DB")
    db_engine = get_db_engine(db_type)

    if not type(columns) == list and columns != "*":
        raise Exception("columns argument must be a list of column names or *")

    columns = ",".join(columns)
    print(f"Retrieving values for {columns}")
    df = pd.read_sql(f'SELECT {columns} FROM {table}', db_engine)

    return df


def load_df_into_db(table_name, db_engine, df):
    schema = table_name.split(".")[0]
    table = table_name.split(".")[-1]

    print(f"Dropping {table_name} if it exists")
    db_engine.execute(f'DROP TABLE IF EXISTS {table_name};')  # Drop the stage table if it exists

    print("Getting sql to create table")
    create_table_statement = pd.io.sql.get_schema(df, table_name)
    replace_values = {
        '"geom" TEXT': '"geom" GEOMETRY', "REAL": "DOUBLE PRECISION"
    }  # Correct data types
    for a, b in replace_values.items():
        create_table_statement = create_table_statement.replace(a, b)

    create_table_statement = create_table_statement.replace(f'"{table_name}"', table_name)

    print(f"Creating {table_name}")
    db_engine.execute(create_table_statement)  # Create the new empty stage table

    print(f"Adding data to {table_name}")
    df.to_sql(con=db_engine, schema=schema, name=table, index=False, if_exists='append')


def run_sql_file_in_db(db_type, sql_file):
    print("Getting connection to run sql files")
    sql = open(sql_file, 'r').read()
    db_connection = get_db_connection(db_type)

    try:
        cur = db_connection.cursor()
        print(f"Running {sql_file}")
        cur.execute(sql)
        db_connection.commit()
    except Exception as e:
        raise e
    finally:
        db_connection.close()

def run_sql_in_db(sql, db_type="viz", insert_mode=False, return_geodataframe=False):
    connection = get_db_connection(db_type)

    try:
        if insert_mode:
            cur = connection.cursor()
            cur.execute(sql)
            connection.commit()
            df = None
        elif return_geodataframe:
            df = gpd.GeoDataFrame.from_postgis(sql, connection)
        else:
            df = pd.read_sql(sql, connection)
    finally:
        connection.close()
    
    return df


def move_db_table(db_connection, origin_table, dest_table, columns, add_oid=True, add_geom_index=True, update_srid=None):
    
    with db_connection as db_connection, db_connection.cursor() as cur:
        cur.execute(f"DROP TABLE IF EXISTS {dest_table};")
        cur.execute(f"SELECT {columns} INTO {dest_table} FROM {origin_table};")
    
        if add_oid:
            print(f"---> Adding an OID to the {dest_table}")
            cur.execute(f'ALTER TABLE {dest_table} ADD COLUMN OID SERIAL PRIMARY KEY;')
        if add_geom_index:
            print(f"---> Adding an spatial index to the {dest_table}")
            cur.execute(f'CREATE INDEX ON {dest_table} USING GIST (geom);')  # Add a spatial index
        if update_srid:
            print(f"---> Updating SRID to {update_srid}")
            cur.execute(f"SELECT UpdateGeometrySRID('{dest_table.split('.')[0]}', '{dest_table.split('.')[1]}', 'geom', {update_srid});")


def create_service_db_tables(df, data_table_name, sql_files, service_table_names, reference_time, past_run=False):
    print("Connecting to viz DB")
    viz_connection = get_db_connection("viz")
    viz_engine = get_db_engine("viz")
    egis_connection = get_db_connection("egis")

    cache_table_name = f"cache.{data_table_name}"

    print(f"Loading data into {cache_table_name}")
    load_df_into_db(cache_table_name, viz_engine, df)

    for sql_file in sql_files:
        print(f"Running sql file {sql_file}")
        run_sql_file_in_db("viz", sql_file)

    for service_table_name in service_table_names:
        # if not a seed time, move to egis db
        if not past_run:
            with viz_connection as db_connection, db_connection.cursor() as cur:
                cur.execute(f"SELECT * FROM publish.{service_table_name} LIMIT 1")
                column_names = [desc[0] for desc in cur.description]
                columns = ', '.join(column_names)

            print(f"Moving {service_table_name} to the EGIS DB")
            try: # Try copying the data
                move_db_table(egis_connection, f"vizprc_publish.{service_table_name}", f"services.{service_table_name}", columns, add_oid=True, add_geom_index=True, update_srid=None)
            except Exception as e: # If it doesn't work initially, try refreshing the foreign schema and try again.
                refresh_fdw_schema(egis_connection, local_schema="vizprc_publish", remote_server="vizprc_db", remote_schema="publish") #Update the foreign data schema - we really don't need to run this all the time, but it's fast, so I'm trying it.
                move_db_table(egis_connection, f"vizprc_publish.{service_table_name}", f"services.{service_table_name}", columns, add_oid=True, add_geom_index=True, update_srid=None) #Copy the publish table from the vizprc db to the egis db, using fdw

        print(f"Creating gpkg for {service_table_name}")
        tempdir = tempfile.mkdtemp()
        gpkg = os.path.join(tempdir, f"{service_table_name}.gpkg")

        gdf = run_sql_in_db(f"select * from publish.{service_table_name}", return_geodataframe=True)

        gdf.to_file(gpkg, index=False)

        s3 = boto3.client("s3")
        s3_cache_key = f'viz_cache/{reference_time.strftime("%Y%m%d")}/{reference_time.strftime("%H%M")}/{service_table_name}.gpkg'
        print(f"Uploading gpkg to {PROCESSED_OUTPUT_BUCKET} at {s3_cache_key}")
        s3.upload_file(gpkg, PROCESSED_OUTPUT_BUCKET, s3_cache_key)

        os.remove(gpkg)

def refresh_fdw_schema(db_connection, local_schema, remote_server, remote_schema):
    with db_connection as db_connection, db_connection.cursor() as cur:
        sql = f"""
        DROP SCHEMA IF EXISTS {local_schema} CASCADE; 
        CREATE SCHEMA {local_schema};
        IMPORT FOREIGN SCHEMA {remote_schema} FROM SERVER {remote_server} INTO {local_schema};
        """
        cur.execute(sql)
    print(f"---> Refreshed {local_schema} foreign schema.")
