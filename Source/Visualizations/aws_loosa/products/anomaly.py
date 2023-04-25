import arcpy
import numpy as np
import pandas as pd
import xarray as xr
from warnings import filterwarnings

# Import Authoritative Datasets and Constants
from aws_loosa.consts import (INSUFFICIENT_DATA_ERROR_CODE)
from aws_loosa.consts.paths import (PERCENTILE_TABLE_5TH, PERCENTILE_TABLE_10TH,
                                        PERCENTILE_TABLE_25TH, PERCENTILE_TABLE_75TH,
                                        PERCENTILE_TABLE_90TH, PERCENTILE_TABLE_95TH,
                                        PERCENTILE_14_TABLE_5TH, PERCENTILE_14_TABLE_10TH,
                                        PERCENTILE_14_TABLE_25TH, PERCENTILE_14_TABLE_75TH,
                                        PERCENTILE_14_TABLE_90TH, PERCENTILE_14_TABLE_95TH)


filterwarnings("ignore")

arcpy.env.overwriteOutput = True


def anomaly(channel_rt_files_list, channel_rt_date_time, anomaly_config=7):
    """
    This function calculates the 7-day streamflow average for all reaches and classifies these into anomaly categories.

    Args:
        channel_rt_files_list (list): A list of all National Water Model (NWM) channel_rt files for each hour over the
            past 7 days.
        channel_rt_date_time (datetime object): The date and time of interest.
        anomaly_config (int): Day configuration to use for percentiles (i.e. 7 day config, 14 day config, etc).

    Returns:
        anomaly_array (array): An array of (Feature ID, Product Version, Valid Time, Anomaly Category, 95th 7-day
            Streamflow Percentile, 90th 7-day Streamflow Percentile, 75th 7-day Streamflow Percentile, 25th 7-day
            Streamflow Percentile, 10th 7-day Streamflow Percentile, 5th 7-day Streamflow Percentile) groups for the
            date and time of interest.
    """
    average_flow_col = f'average_flow_{anomaly_config}day'
    anom_col = f'anom_cat_{anomaly_config}day'

    if anomaly_config == 7:
        percentile_5 = PERCENTILE_TABLE_5TH
        percentile_10 = PERCENTILE_TABLE_10TH
        percentile_25 = PERCENTILE_TABLE_25TH
        percentile_75 = PERCENTILE_TABLE_75TH
        percentile_90 = PERCENTILE_TABLE_90TH
        percentile_95 = PERCENTILE_TABLE_95TH
    elif anomaly_config == 14:
        percentile_5 = PERCENTILE_14_TABLE_5TH
        percentile_10 = PERCENTILE_14_TABLE_10TH
        percentile_25 = PERCENTILE_14_TABLE_25TH
        percentile_75 = PERCENTILE_14_TABLE_75TH
        percentile_90 = PERCENTILE_14_TABLE_90TH
        percentile_95 = PERCENTILE_14_TABLE_95TH
    else:
        raise Exception("Anomaly config must be 7 or 14 for the appropriate percentile files")

    # Import Feature IDs
    arcpy.AddMessage("-->Looping through files to get streamflow sum")
    df = pd.DataFrame()
    for file in channel_rt_files_list:
        ds_file = xr.open_dataset(file)
        df_file = ds_file['streamflow'].to_dataframe()
        df_file['streamflow']  = df_file['streamflow'] * 35.3147  # convert streamflow from cms to cfs

        if df.empty:
            df = df_file
            df = df.rename(columns={"streamflow": "streamflow_sum"})
        else:
            df['streamflow_sum'] += df_file['streamflow']

    df[average_flow_col] = df['streamflow_sum'] / len(channel_rt_files_list)
    df = df.drop(columns=['streamflow_sum'])
    df[average_flow_col] = df[average_flow_col].round(2)

    # Import Percentile Data
    arcpy.AddMessage("-->Importing percentile data:")

    date = int(channel_rt_date_time.strftime("%j")) - 1  # retrieves the date in integer form from channel_rt_date_time

    arcpy.AddMessage(f"---->Retrieving {anomaly_config} day 5th percentiles...")
    ds_perc = xr.open_dataset(percentile_5)
    df_perc = ds_perc.sel(time=date)['streamflow'].to_dataframe()
    df_perc = df_perc.rename(columns={"streamflow": "prcntle_5"})
    df_perc['prcntle_5'] = (df_perc['prcntle_5'] * 35.3147).round(2)  # convert streamflow from cms to cfs
    df = df.join(df_perc)

    arcpy.AddMessage(f"---->Retrieving {anomaly_config} day 10th percentiles...")
    ds_perc = xr.open_dataset(percentile_10)
    df_perc = ds_perc.sel(time=date)['streamflow'].to_dataframe()
    df_perc = df_perc.rename(columns={"streamflow": "prcntle_10"})
    df_perc['prcntle_10'] = (df_perc['prcntle_10'] * 35.3147).round(2)  # convert streamflow from cms to cfs
    df = df.join(df_perc)

    arcpy.AddMessage(f"---->Retrieving {anomaly_config} day 25th percentiles...")
    ds_perc = xr.open_dataset(percentile_25)
    df_perc = ds_perc.sel(time=date)['streamflow'].to_dataframe()
    df_perc = df_perc.rename(columns={"streamflow": "prcntle_25"})
    df_perc['prcntle_25'] = (df_perc['prcntle_25'] * 35.3147).round(2)  # convert streamflow from cms to cfs
    df = df.join(df_perc)

    arcpy.AddMessage(f"---->Retrieving {anomaly_config} day 75th percentiles...")
    ds_perc = xr.open_dataset(percentile_75)
    df_perc = ds_perc.sel(time=date)['streamflow'].to_dataframe()
    df_perc = df_perc.rename(columns={"streamflow": "prcntle_75"})
    df_perc['prcntle_75'] = (df_perc['prcntle_75'] * 35.3147).round(2)  # convert streamflow from cms to cfs
    df = df.join(df_perc)

    arcpy.AddMessage(f"---->Retrieving {anomaly_config} day 90th percentiles...")
    ds_perc = xr.open_dataset(percentile_90)
    df_perc = ds_perc.sel(time=date)['streamflow'].to_dataframe()
    df_perc = df_perc.rename(columns={"streamflow": "prcntle_90"})
    df_perc['prcntle_90'] = (df_perc['prcntle_90'] * 35.3147).round(2)  # convert streamflow from cms to cfs
    df = df.join(df_perc)

    arcpy.AddMessage(f"---->Retrieving {anomaly_config} day 95th percentiles...")
    ds_perc = xr.open_dataset(percentile_95)
    df_perc = ds_perc.sel(time=date)['streamflow'].to_dataframe()
    df_perc = df_perc.rename(columns={"streamflow": "prcntle_95"})
    df_perc['prcntle_95'] = (df_perc['prcntle_95'] * 35.3147).round(2)  # convert streamflow from cms to cfs
    df = df.join(df_perc)

    arcpy.AddMessage("---->Creating percentile dictionary...")
    df[anom_col] = np.nan
    df.loc[(df[average_flow_col] >= df['prcntle_95']) & df[anom_col].isna(), anom_col] = "High (> 95th)"
    df.loc[(df[average_flow_col] >= df['prcntle_90']) & df[anom_col].isna(), anom_col] = "Much Above Normal (91st - 95th)"  # noqa: E501
    df.loc[(df[average_flow_col] >= df['prcntle_75']) & df[anom_col].isna(), anom_col] = "Above Normal (76th - 90th)"
    df.loc[(df[average_flow_col] >= df['prcntle_25']) & df[anom_col].isna(), anom_col] = "Normal (26th - 75th)"
    df.loc[(df[average_flow_col] >= df['prcntle_10']) & df[anom_col].isna(), anom_col] = "Below Normal (11th - 25th))"
    df.loc[(df[average_flow_col] >= df['prcntle_5']) & df[anom_col].isna(), anom_col] = "Much Below Normal (6th - 10th)"
    df.loc[(df[average_flow_col] < df['prcntle_5']) & df[anom_col].isna(), anom_col] = "Low (<= 5th)"
    df.loc[df[anom_col].isna(), anom_col] = "Insufficient Data Available"
    df = df.replace(round(INSUFFICIENT_DATA_ERROR_CODE * 35.3147, 2), "No Data")

    return df
