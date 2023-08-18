################################################################################
################################ Viz DB Ingest ################################# 
################################################################################
"""
This function downloads a file from S3 and ingets it into the vizprocessing RDS
database.

Args:
    event (dictionary): The event passed from the state machine.
    context (object): Automatic metadata regarding the invocation.
    
Returns:
    dictionary: The details of the file that was ingested, to be returned to the state machine.
"""
################################################################################
import os
import boto3
import json
from datetime import datetime
import numpy as np
import xarray as xr
import pandas as pd
from io import StringIO
import re
from viz_classes import database
from viz_lambda_shared_funcs import check_if_file_exists

s3 = boto3.client('s3')
s3_resource = boto3.resource('s3')

class MissingS3FileException(Exception):
    """ my custom exception class """

def lambda_handler(event, context):

    target_table = event['target_table']
    target_cols = event['target_cols']
    file = event['file']
    bucket = event['bucket']
    reference_time = event['reference_time']
    keep_flows_at_or_above = event['keep_flows_at_or_above']
    reference_time_dt = datetime.strptime(reference_time, '%Y-%m-%d %H:%M:%S')
    
    print(f"Checking existance of {file} on S3/Google Cloud/Para Nomads.")
    download_path = check_if_file_exists(bucket, file, download=True)
    
    if not target_table:
        dump_dict = {
            "file": file,
            "target_table": target_table,
            "reference_time": reference_time,
            "rows_imported": 0
        }
        return json.dumps(dump_dict)
    
    viz_db = database(db_type="viz")
    with viz_db.get_db_connection() as connection:
        cursor = connection.cursor()
        try:
            nwm_version = 0

            if file.endswith('.nc'):
                ds = xr.open_dataset(download_path)
                ds_vars = [var for var in ds.variables]

                if not target_cols:
                    target_cols = ds_vars

                ds['forecast_hour'] = int(re.findall("(\d{8})/[a-z0-9_]*/.*t(\d{2})z.*[ftm](\d*)\.", file)[0][-1])
                
                try:
                    ds['nwm_vers'] = float(ds.NWM_version_number.replace("v",""))
                except:
                    print("NWM_version_number property is not available in the netcdf file")

                drop_vars = [var for var in ds_vars if var not in target_cols]
                df = ds.to_dataframe().reset_index()
                df = df.drop(columns=drop_vars)
                ds.close()
                if 'streamflow' in ds_vars:
                    df = df.loc[df['streamflow'] >= keep_flows_at_or_above].round({'streamflow': 2}).copy()  # noqa

            elif file.endswith('.csv'):
                df = pd.read_csv(download_path)
                for column in df:  # Replace any 'None' strings with nulls
                    df[column].replace('None', np.nan, inplace=True)
                df = df.copy()
            else:
                print("File format not supported.")
                exit()

            print(f"--> Preparing and Importing {file}")
            f = StringIO()  # Use StringIO to store the temporary text file in memory (faster than on disk)
            df.to_csv(f, sep='\t', index=False, header=False)
            f.seek(0)
            with viz_db.get_db_connection() as connection:
                cursor = connection.cursor()
                #cursor.copy_from(f, target_table, sep='\t', null='')  # This is the command that actual copies the data to db
                cursor.copy_expert(f"COPY {target_table} FROM STDIN WITH DELIMITER E'\t' null as ''", f)
                connection.commit()

            print(f"--> Import of {len(df)} rows Complete. Removing {download_path} and closing db connection.")
            os.remove(download_path)
    
        except Exception as e:
            print(f"Error: {e}")
            raise e
    
    dump_dict = {
                        "file": file,
                        "target_table": target_table,
                        "reference_time": reference_time,
                        "rows_imported": len(df),
                        "nwm_version": nwm_version
                    }
    return json.dumps(dump_dict)    # Return some info on the import