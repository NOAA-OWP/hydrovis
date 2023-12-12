import numpy as np
import pandas as pd
import xarray as xr
import tempfile
import boto3
import os
from viz_lambda_shared_funcs import check_if_file_exists, organize_input_files

INSUFFICIENT_DATA_ERROR_CODE = -9998
PERCENTILE_TABLE_5TH = "viz_authoritative_data/derived_data/nwm_v21_7_day_average_percentiles/final_7day_all_5th_perc.nc"
PERCENTILE_TABLE_10TH = "viz_authoritative_data/derived_data/nwm_v21_7_day_average_percentiles/final_7day_all_10th_perc.nc"
PERCENTILE_TABLE_25TH = "viz_authoritative_data/derived_data/nwm_v21_7_day_average_percentiles/final_7day_all_25th_perc.nc"
PERCENTILE_TABLE_75TH = "viz_authoritative_data/derived_data/nwm_v21_7_day_average_percentiles/final_7day_all_75th_perc.nc"
PERCENTILE_TABLE_90TH = "viz_authoritative_data/derived_data/nwm_v21_7_day_average_percentiles/final_7day_all_90th_perc.nc"
PERCENTILE_TABLE_95TH = "viz_authoritative_data/derived_data/nwm_v21_7_day_average_percentiles/final_7day_all_95th_perc.nc"
PERCENTILE_14_TABLE_5TH = "viz_authoritative_data/derived_data/nwm_v21_14_day_average_percentiles/final_14day_all_5th_perc.nc"
PERCENTILE_14_TABLE_10TH = "viz_authoritative_data/derived_data/nwm_v21_14_day_average_percentiles/final_14day_all_10th_perc.nc"
PERCENTILE_14_TABLE_25TH = "viz_authoritative_data/derived_data/nwm_v21_14_day_average_percentiles/final_14day_all_25th_perc.nc"
PERCENTILE_14_TABLE_75TH = "viz_authoritative_data/derived_data/nwm_v21_14_day_average_percentiles/final_14day_all_75th_perc.nc"
PERCENTILE_14_TABLE_90TH = "viz_authoritative_data/derived_data/nwm_v21_14_day_average_percentiles/final_14day_all_90th_perc.nc"
PERCENTILE_14_TABLE_95TH = "viz_authoritative_data/derived_data/nwm_v21_14_day_average_percentiles/final_14day_all_95th_perc.nc"

def run_anomaly(reference_time, fileset_bucket, fileset, output_file_bucket, output_file, auth_data_bucket, anomaly_config=7):
    average_flow_col = f'average_flow_{anomaly_config}day'
    anom_col = f'anom_cat_{anomaly_config}day'
    
    ##### Data Prep #####
    if anomaly_config == 7:
        download_subfolder = "7_day"
        percentile_5 = check_if_file_exists(auth_data_bucket, PERCENTILE_TABLE_5TH, download=True, download_subfolder=download_subfolder)
        percentile_10 = check_if_file_exists(auth_data_bucket, PERCENTILE_TABLE_10TH, download=True, download_subfolder=download_subfolder)
        percentile_25 = check_if_file_exists(auth_data_bucket, PERCENTILE_TABLE_25TH, download=True, download_subfolder=download_subfolder)
        percentile_75 = check_if_file_exists(auth_data_bucket, PERCENTILE_TABLE_75TH, download=True, download_subfolder=download_subfolder)
        percentile_90 = check_if_file_exists(auth_data_bucket, PERCENTILE_TABLE_90TH, download=True, download_subfolder=download_subfolder)
        percentile_95 = check_if_file_exists(auth_data_bucket, PERCENTILE_TABLE_95TH, download=True, download_subfolder=download_subfolder)
    elif anomaly_config == 14:
        download_subfolder = "14_day"
        percentile_5 = check_if_file_exists(auth_data_bucket, PERCENTILE_14_TABLE_5TH, download=True, download_subfolder=download_subfolder)
        percentile_10 = check_if_file_exists(auth_data_bucket, PERCENTILE_14_TABLE_10TH, download=True, download_subfolder=download_subfolder)
        percentile_25 = check_if_file_exists(auth_data_bucket, PERCENTILE_14_TABLE_25TH, download=True, download_subfolder=download_subfolder)
        percentile_75 = check_if_file_exists(auth_data_bucket, PERCENTILE_14_TABLE_75TH, download=True, download_subfolder=download_subfolder)
        percentile_90 = check_if_file_exists(auth_data_bucket, PERCENTILE_14_TABLE_90TH, download=True, download_subfolder=download_subfolder)
        percentile_95 = check_if_file_exists(auth_data_bucket, PERCENTILE_14_TABLE_95TH, download=True, download_subfolder=download_subfolder)
    else:
        raise Exception("Anomaly config must be 7 or 14 for the appropriate percentile files")

    print("Downloading NWM Data")
    input_files = organize_input_files(fileset_bucket, fileset, download_subfolder=reference_time.strftime('%Y%m%d'))
    
    #Get NWM version from first file
    with xr.open_dataset(input_files[0]) as first_file:
        nwm_vers = first_file.NWM_version_number.replace("v","")
    
    # Import Feature IDs
    print("-->Looping through files to get streamflow sum")
    df = pd.DataFrame()
    for file in input_files:
        ds_file = xr.open_dataset(file)
        df_file = ds_file['streamflow'].to_dataframe()
        df_file['streamflow']  = df_file['streamflow'] * 35.3147  # convert streamflow from cms to cfs

        if df.empty:
            df = df_file
            df = df.rename(columns={"streamflow": "streamflow_sum"})
        else:
            df['streamflow_sum'] += df_file['streamflow']
        os.remove(file)

    df[average_flow_col] = df['streamflow_sum'] / len(input_files)
    df = df.drop(columns=['streamflow_sum'])
    df[average_flow_col] = df[average_flow_col].round(2)

    # Import Percentile Data
    print("-->Importing percentile data:")

    date = int(reference_time.strftime("%j")) - 1  # retrieves the date in integer form from reference_time

    print(f"---->Retrieving {anomaly_config} day 5th percentiles...")
    ds_perc = xr.open_dataset(percentile_5)
    df_perc = ds_perc.sel(time=date)['streamflow'].to_dataframe()
    df_perc = df_perc.rename(columns={"streamflow": "prcntle_5"})
    df_perc['prcntle_5'] = (df_perc['prcntle_5'] * 35.3147).round(2)  # convert streamflow from cms to cfs
    df = df.join(df_perc)

    print(f"---->Retrieving {anomaly_config} day 10th percentiles...")
    ds_perc = xr.open_dataset(percentile_10)
    df_perc = ds_perc.sel(time=date)['streamflow'].to_dataframe()
    df_perc = df_perc.rename(columns={"streamflow": "prcntle_10"})
    df_perc['prcntle_10'] = (df_perc['prcntle_10'] * 35.3147).round(2)  # convert streamflow from cms to cfs
    df = df.join(df_perc)

    print(f"---->Retrieving {anomaly_config} day 25th percentiles...")
    ds_perc = xr.open_dataset(percentile_25)
    df_perc = ds_perc.sel(time=date)['streamflow'].to_dataframe()
    df_perc = df_perc.rename(columns={"streamflow": "prcntle_25"})
    df_perc['prcntle_25'] = (df_perc['prcntle_25'] * 35.3147).round(2)  # convert streamflow from cms to cfs
    df = df.join(df_perc)

    print(f"---->Retrieving {anomaly_config} day 75th percentiles...")
    ds_perc = xr.open_dataset(percentile_75)
    df_perc = ds_perc.sel(time=date)['streamflow'].to_dataframe()
    df_perc = df_perc.rename(columns={"streamflow": "prcntle_75"})
    df_perc['prcntle_75'] = (df_perc['prcntle_75'] * 35.3147).round(2)  # convert streamflow from cms to cfs
    df = df.join(df_perc)

    print(f"---->Retrieving {anomaly_config} day 90th percentiles...")
    ds_perc = xr.open_dataset(percentile_90)
    df_perc = ds_perc.sel(time=date)['streamflow'].to_dataframe()
    df_perc = df_perc.rename(columns={"streamflow": "prcntle_90"})
    df_perc['prcntle_90'] = (df_perc['prcntle_90'] * 35.3147).round(2)  # convert streamflow from cms to cfs
    df = df.join(df_perc)

    print(f"---->Retrieving {anomaly_config} day 95th percentiles...")
    ds_perc = xr.open_dataset(percentile_95)
    df_perc = ds_perc.sel(time=date)['streamflow'].to_dataframe()
    df_perc = df_perc.rename(columns={"streamflow": "prcntle_95"})
    df_perc['prcntle_95'] = (df_perc['prcntle_95'] * 35.3147).round(2)  # convert streamflow from cms to cfs
    df = df.join(df_perc)

    print("---->Creating percentile dictionary...")
    df[anom_col] = np.nan
    df.loc[(df[average_flow_col] >= df['prcntle_95']) & df[anom_col].isna(), anom_col] = "High (> 95th)"
    df.loc[(df[average_flow_col] >= df['prcntle_90']) & df[anom_col].isna(), anom_col] = "Much Above Normal (91st - 95th)"  # noqa: E501
    df.loc[(df[average_flow_col] >= df['prcntle_75']) & df[anom_col].isna(), anom_col] = "Above Normal (76th - 90th)"
    df.loc[(df[average_flow_col] >= df['prcntle_25']) & df[anom_col].isna(), anom_col] = "Normal (26th - 75th)"
    df.loc[(df[average_flow_col] >= df['prcntle_10']) & df[anom_col].isna(), anom_col] = "Below Normal (11th - 25th))"
    df.loc[(df[average_flow_col] >= df['prcntle_5']) & df[anom_col].isna(), anom_col] = "Much Below Normal (6th - 10th)"
    df.loc[(df[average_flow_col] < df['prcntle_5']) & df[anom_col].isna(), anom_col] = "Low (<= 5th)"
    df.loc[df[anom_col].isna(), anom_col] = "Insufficient Data Available"
    df = df.replace(round(INSUFFICIENT_DATA_ERROR_CODE * 35.3147, 2), None)
    df['nwm_vers'] = nwm_vers

    print("Uploading output CSV file to S3")
    s3 = boto3.client('s3')
    tempdir = tempfile.mkdtemp()
    tmp_ouput_path = os.path.join(tempdir, f"temp_output.csv")
    df = df.reset_index()
    df.to_csv(tmp_ouput_path, index=False)
    s3.upload_file(tmp_ouput_path, output_file_bucket, output_file)
    print(f"--- Uploaded to {output_file_bucket}:{output_file}")
    os.remove(tmp_ouput_path)