########################################################################################################################################
## This script will load all of the FEMA USA Structures feature classes in a given folder into the viz processing database (notes below)
## WARNING: Use with caution, this writes to the database.
## Requirements: A folder full of unzipped USA Structures GDBs (sub folders don't matter). An External schema in the database.
## Source: https://disasters.geoplatform.gov/publicdata/Partners/ORNL/USA_Structures/
########################################################################################################################################
import os
import arcpy
import psycopg2
from feature_class_to_csv import convert_feature_class_to_csv

##########################################
def import_building_footprints_folder(schema, table_name, building_footprint_folder, csv_folder):
    table = f"{schema}.{table_name}"
    
    gdbs = get_gdb_list(building_footprint_folder)
    for gdb in gdbs:
        try:
            arcpy.env.workspace = gdb
            feature_class_name = arcpy.ListFeatureClasses()[0] #assumes only one feature class per gdb
            feature_class = os.path.join(gdb, feature_class_name)
            csv_file = os.path.join(csv_folder, feature_class_name + '.csv')
            if os.path.isfile(csv_file) is False:
                convert_feature_class_to_csv(feature_class, csv_file, "SHAPE@WKT")
            with psycopg2.connect(f"host={db_host} dbname={db_name} user={db_user} password={db_password}") as connection:
                cursor = connection.cursor()
                with open(csv_file, 'r') as f:
                    cursor.copy_expert(f"COPY {table} FROM STDIN WITH DELIMITER ',' CSV HEADER null as ''", f)
                connection.commit()
            print(f"Imported {feature_class_name}")
            os.remove(csv_file)
        except Exception as e:
            print(f"Failed on gdb: {gdb}")
            raise(e)

##########################################
def get_gdb_list(dir):
    listOfFile = os.listdir(dir)
    allFiles = list()
    for entry in listOfFile:
        fullPath = os.path.join(dir, entry)
        if os.path.isdir(fullPath):
            if '.gdb' in fullPath:
                allFiles.append(fullPath)
            else:
                allFiles = allFiles + get_gdb_list(fullPath)    
    return allFiles

##########################################
def pre_data(schema, table):
    sql = f"""
    DROP TABLE IF EXISTS {schema}.{table};
    CREATE TABLE IF NOT EXISTS {schema}.{table}
        (
            objectid bigint,
            geom geometry,
            build_id bigint,
            occ_cls text,
            prim_occ text,
            sec_occ text,
            prop_addr text,
            prop_city text,
            prop_st text,
            prop_zip text,
            outbldg text,
            height double precision,
            sqmeters double precision,
            sqfeet double precision,
            h_adj_elev double precision,
            l_adj_elev double precision,
            fips text,
            censuscode text,
            prod_date text,
            source text,
            usng text,
            longitude double precision,
            latitude double precision,
            image_name text,
            image_date text,
            val_method text,
            remarks text,
            uuid text,
            Shape_Length double precision,
            Shape_Area double precision
        )
    """
    with psycopg2.connect(f"host={db_host} dbname={db_name} user={db_user} password={db_password}") as connection:
        cursor = connection.cursor()
        cursor.execute(sql)
        connection.commit()
    print(f"Completed pre_data on {schema}.{table}")

##########################################
def post_data(schema, table):
    sql = f"""
    ALTER TABLE {schema}.{table} ADD COLUMN geom_3857 geometry(Geometry, 3857);
    SELECT updateGeometrySRID('{schema}', '{table}','geom', 4326);
    UPDATE {schema}.{table} SET geom_3857 = ST_Transform(geom, 3857);
    ALTER TABLE {schema}.{table} DROP COLUMN geom;
    ALTER TABLE {schema}.{table} RENAME COLUMN geom_3857 TO geom;
    CREATE INDEX building_footprints_fema_geom_idx ON {schema}.{table} USING GIST (geom);
    ALTER TABLE {schema}.{table} DROP COLUMN shape_area, DROP COLUMN shape_length;
    
    -- Update state column to be complete --requires states table in derived schema
    UPDATE {schema}.{table} AS buildings
    SET prop_st = name
    FROM derived.states AS states WHERE left(fips, 2) = TO_CHAR(statefp, 'fm00')
    """
    with psycopg2.connect(f"host={db_host} dbname={db_name} user={db_user} password={db_password}") as connection:
        cursor = connection.cursor()
        cursor.execute(sql)
        connection.commit()
    print(f"Completed post_data on {schema}.{table}")

########################################################################################################################################
if __name__ == '__main__':
    db_host = "hydrovis-ti-viz-processing.c4vzypepnkx3.us-east-1.rds.amazonaws.com"
    db_name = "vizprocessing"
    db_user = "viz_proc_admin_rw_user"
    db_password = ""
    schema = "external"
    table = "building_footprints_fema_pa"
    building_footprint_folder = r"C:\Users\Administrator\Downloads\Deliverable20211229PA" #Point this at a folder that has all the unzipped gdbs of the FEMA USA Structures dataset.
    csv_folder = r"C:\Users\Administrator\Desktop\BuildingFootprints" # Set this to the folder that you want to use for temporary storage of CSV files.
    pre_data(schema, table)
    import_building_footprints_folder(schema, table, building_footprint_folder, csv_folder)
    post_data(schema, table)