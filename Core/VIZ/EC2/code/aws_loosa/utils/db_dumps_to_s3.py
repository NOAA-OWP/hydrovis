# This script can be used to automate the pg_dump and S3 upload process, prior to a hydrovis terraform deployment
import os

pg_dump_exe_location = r"C:/users/administrator/desktop/temp_db_dumps" #Copy pg_dump.exe here. This must be in a user directory, you will have permission errors with system folder. No spaces.
local_output_folder = r"C:/users/administrator/desktop/temp_db_dumps"
s3_output_bucket = "hydrovis-ti-redeploy-backup" #Set these to None if you don't want to upload to S3
s3_output_path = "tyler_backup_mess/dump_test/" #Set these to None if you don't want to upload to S3

###################################
def dump_schema(schema, output_folder, file_prefix="", dump_type='data_and_schema'):
    output_file = os.path.join(output_folder, file_prefix + schema + '.dump')
    command = f"""{pg_dump_exe_location}/pg_dump.exe --host={db_host} --dbname={db_name} --username={db_user} --schema={schema} --format=c --file={output_file}"""
    if dump_type == 'schema_only':
        command += ' --schema-only'
    os.system(command)

    if s3_output_path:
        import boto3
        s3 = boto3.client('s3')
        s3.upload_file(output_file, s3_output_bucket, os.path.join(s3_output_path, os.path.basename(output_file)))
        os.remove(output_file)

################ Viz Database ###################
db_host = "hydrovis-ti-viz-processing.c4vzypepnkx3.us-east-1.rds.amazonaws.com"
db_name = "vizprocessing"
db_user = "viz_proc_dev_rw_user"
os.environ['PGPASSWORD'] = ""
dump_schema("admin", local_output_folder, file_prefix="vizDB_")
dump_schema("derived", local_output_folder, file_prefix="vizDB_")
dump_schema("ingest", local_output_folder, file_prefix="vizDB_", dump_type="schema_only")
dump_schema("cache", local_output_folder, file_prefix="vizDB_", dump_type="schema_only")
dump_schema("publish", local_output_folder, file_prefix="vizDB_", dump_type="schema_only")

################ EGIS Database ###################
db_host = "hv-ti-egis-rds-pg-egdb.c4vzypepnkx3.us-east-1.rds.amazonaws.com"
db_name = "hydrovis"
db_user = "hydrovis"
os.environ['PGPASSWORD'] = ""
dump_schema("services", local_output_folder, file_prefix="egisDB_", dump_type="schema_only")
# dump_schema("fim_catchments", local_output_folder, file_prefix="egisDB_")
# dump_schema("reference", local_output_folder, file_prefix="egisDB_")