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
import requests
import boto3
import json
import numpy as np
import xarray as xr
import pandas as pd
from io import StringIO
from viz_classes import database, s3_file

s3 = boto3.client('s3')
s3_resource = boto3.resource('s3')

class MissingS3FileException(Exception):
    """ my custom exception class """
    
def lambda_handler(event, context):

    target_table = event['target_table']
    file = event['file']
    bucket = event['bucket']
    reference_time = event['reference_time']
    keep_flows_at_or_above = event['keep_flows_at_or_above']
    
    print(f"Checking existance of {file} on S3/Google Cloud/Para Nomads.")
    file = check_if_file_exists(bucket, file)
    
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
            download_path = f'/tmp/{os.path.basename(file)}'
            print(f"--> Downloading {file} to {download_path}")
            if 'https' in file:
                open(download_path, 'wb').write(requests.get(file, allow_redirects=True).content)
            else:
                s3.download_file(bucket, file, download_path)
    
            nwm_version = 0
            if file[-12:] == 'max_flows.nc':
                # Load the NetCDF file into a dataframe
                ds = xr.open_dataset(download_path)
                df = ds.to_dataframe().reset_index()
                ds.close()
                df_toLoad = df.loc[df['streamflow'] >= keep_flows_at_or_above].round({'streamflow': 2}).copy()  # noqa
    
            elif file[-3:] == '.nc':
                # Load the NetCDF file into a dataframe
                drop_vars = ['crs', 'nudge', 'velocity', 'qSfcLatRunoff', 'qBucket', 'qBtmVertRunoff']
                ds = xr.open_dataset(download_path, drop_variables=drop_vars)
                ds['time_step'] = (((ds['time'] - ds['reference_time'])) / np.timedelta64(1, 'h')).astype(int)
                ds['nwm_vers'] = float(ds.NWM_version_number.replace("v",""))
                df = ds.to_dataframe().reset_index()
                ds.close()
    
                # Only include reference time in the insert if specified
                df_toLoad = df[['feature_id', 'time_step', 'streamflow', 'nwm_vers']]
                cursor.execute(f"CREATE TABLE IF NOT EXISTS {target_table} (feature_id integer, forecast_hour integer, "
                                "streamflow double precision, nwm_vers double precision)")
    
                # Filter out any streamflow data below the specificed threshold
                df_toLoad = df_toLoad.loc[df_toLoad['streamflow'] >= keep_flows_at_or_above].round({'streamflow': 2}).copy()  # noqa
    
            elif file[-4:] == '.csv':
                df = pd.read_csv(download_path)
                for column in df:  # Replace any 'None' strings with nulls
                    df[column].replace('None', np.nan, inplace=True)
                df_toLoad = df.copy()
            else:
                print("File format not supported.")
                exit()
    
            print(f"--> Preparing and Importing {file}")
            f = StringIO()  # Use StringIO to store the temporary text file in memory (faster than on disk)
            df_toLoad.to_csv(f, sep='\t', index=False, header=False)
            f.seek(0)
            #cursor.copy_from(f, target_table, sep='\t', null='')  # This is the command that actual copies the data to db
            cursor.copy_expert(f"COPY {target_table} FROM STDIN WITH DELIMITER E'\t' null as ''", f)
            connection.commit()
    
            print(f"--> Import of {len(df_toLoad)} rows Complete. Removing {download_path} and closing db connection.")
            os.remove(download_path)
    
        except Exception as e:
            print(f"Error: {e}")
            raise e
    
    dump_dict = {
                        "file": file,
                        "target_table": target_table,
                        "reference_time": reference_time,
                        "rows_imported": len(df_toLoad),
                        "nwm_version": nwm_version
                    }
    return json.dumps(dump_dict)    # Return some info on the import

def check_if_file_exists(bucket, file):
    if "https" in file:
        if requests.head(file).status_code == 200:
            print(f"{file} exists.")
            return file
        else:
            raise Exception(f"https file doesn't seem to exist: {file}")
        
    else:
        if s3_file(bucket, file).check_existence():
            print("File exists on S3.")
            return file
        else:
            if "/prod" in file:
                google_file = file.replace('common/data/model/com/nwm/prod', 'https://storage.googleapis.com/national-water-model')
                if requests.head(google_file).status_code == 200:
                    print("File does not exist on S3 (even though it should), but does exists on Google Cloud.")
                    return google_file
            elif "/para" in file:
                para_nomads_file = file.replace("common/data/model/com/nwm/para", "https://para.nomads.ncep.noaa.gov/pub/data/nccf/com/nwm/para")
                if requests.head(para_nomads_file).status_code == 200:
                    print("File does not exist on S3 (even though it should), but does exists on NOMADS para.")
                    
                    download_path = f'/tmp/{os.path.basename(para_nomads_file)}'
                    
                    
                    tries = 0
                    while tries < 3:
                        open(download_path, 'wb').write(requests.get(para_nomads_file, allow_redirects=True).content)
                        
                        try:
                            xr.open_dataset(download_path)
                            tries = 3
                        except:
                            print(f"Failed to open {download_path}. Retrying in case file was corrupted on download")
                            os.remove(download_path)
                            tries +=1
                    
                    print(f"Saving {file} to {bucket} for archiving")
                    s3.upload_file(download_path, bucket, file)
                    os.remove(download_path)
                    return file
            else:
                raise Exception("Code could not handle request for file")


        raise MissingS3FileException(f"{file} does not exist on S3.")