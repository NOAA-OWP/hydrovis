# This script can be used to automate the pg_dump and S3 upload process, prior to a hydrovis terraform deployment
import os

version_suffix = '2023_0214'
pg_dump_exe_location = r"C:/users/administrator/desktop/temp_db_dumps" #Copy pg_dump.exe here. This must be in a user directory, you will have permission errors with system folder. No spaces.
local_output_folder = r"C:/users/administrator/desktop/temp_db_dumps"
s3_output_bucket = "hydrovis-ti-deployment-us-east-1" #Set these to None if you don't want to upload to S3
s3_output_path = "viz/db_pipeline/db_dumps/" #Set these to None if you don't want to upload to S3

###################################
def dump_schema(schema, output_folder, file_prefix, version_suffix, dump_type='data_and_schema'):
    print(f"Starting {file_prefix}{schema}")
    output_file = os.path.join(output_folder, file_prefix + schema + '_' + version_suffix + '.dump')
    command = f"""{pg_dump_exe_location}/pg_dump.exe --host={db_host} --dbname={db_name} --username={db_user} --schema={schema} --format=c --file={output_file}"""
    if dump_type == 'schema_only':
        command += ' --schema-only'
    os.system(command)

    if s3_output_path:
        import boto3
        s3 = boto3.client('s3')
        s3.upload_file(output_file, s3_output_bucket, os.path.join(s3_output_path, os.path.basename(output_file)))
        os.remove(output_file)
        print(f"Uploaded to S3: {output_file}")

################ Viz Database ###################
db_host = "hydrovis-ti-viz-processing.c4vzypepnkx3.us-east-1.rds.amazonaws.com"
db_name = "vizprocessing"
db_user = "viz_proc_admin_rw_user"
os.environ['PGPASSWORD'] = ""
dump_schema("admin", local_output_folder, file_prefix="vizDB_", version_suffix=version_suffix)
dump_schema("derived", local_output_folder, file_prefix="vizDB_", version_suffix=version_suffix)
dump_schema("ingest", local_output_folder, file_prefix="vizDB_", version_suffix=version_suffix, dump_type="schema_only")
dump_schema("cache", local_output_folder, file_prefix="vizDB_", version_suffix=version_suffix, dump_type="schema_only")
dump_schema("publish", local_output_folder, file_prefix="vizDB_", version_suffix=version_suffix, dump_type="schema_only")
dump_schema("archive", local_output_folder, file_prefix="vizDB_", version_suffix=version_suffix, dump_type="schema_only")
dump_schema("external", local_output_folder, file_prefix="vizDB_", version_suffix=version_suffix)
dump_schema("dev", local_output_folder, file_prefix="vizDB_", version_suffix=version_suffix)
dump_schema("scenarios", local_output_folder, file_prefix="vizDB_", version_suffix=version_suffix)

################ EGIS Database ###################
db_host = "hv-ti-egis-rds-pg-egdb.c4vzypepnkx3.us-east-1.rds.amazonaws.com"
db_name = "hydrovis"
db_user = "hydrovis"
os.environ['PGPASSWORD'] = ""
dump_schema("services", local_output_folder, file_prefix="egisDB_", version_suffix=version_suffix, dump_type="schema_only")
dump_schema("fim_catchments", local_output_folder, file_prefix="egisDB_", version_suffix=version_suffix)
dump_schema("reference", local_output_folder, file_prefix="egisDB_", version_suffix=version_suffix)