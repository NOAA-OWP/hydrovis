"""
NWM 12-Hour Rapid Onset Flooding Probability Forecast

Description: This script calculates rapid onset flooding probability across the 7 most recent SRF forecasts.

Created: 9 November 2021
Author: Tyler Schrag(tyler.schrag@noaa.gov)

Updated: 06 December 2021
Author: Tyler Schrag (tyler.schrag@noaa.gov)
Comments: Added new create_weighted_mean_huc_hotspots function. Add Stream Order filter.

"""
import pandas as pd
import numpy as np
import xarray as xr
import re
from datetime import datetime, timedelta
from itertools import cycle, islice

from aws_loosa.ec2.consts import CFS_FROM_CMS
from aws_loosa.ec2.utils.shared_funcs import get_db_values

pd.options.mode.chained_assignment = None

def srf_rapid_onset_probability(a_event_time, a_input_files, percent_change_threshold=100, high_water_hour_threshold=6,
                                stream_reaches_at_or_below=4):
    """
    This function takes the past current and past 6 SRF forecasts and uses them as ensemble members to calculate
    SRF Rapid Onset Flooding Probability.

    Args:
        a_event_time(datetime): Reference time
        a_input_files(list): List of input files
        percent_change_threshold (int): Number representing the percent change threshold for rapid onset criteria.
        high_water_hour_threshold (int): The number of hours that can pass within percent change threshold and high flow threshold
            conditions to be considered rapid onset.
        stream_reaches_at_or_below (int): The stream order threshold by which to consider reaches.
    """
    reference_time = a_event_time  # datetime.strptime(a_event_time, '%Y-%m-%dT%H:%M:%SZ')
    hours_in_day = list(range(0, 24))
    files = {}
    dataframes = {}

    df_high_water_threshold = get_db_values("derived.recurrence_flows_conus", ["feature_id", "high_water_threshold"])
    df_high_water_threshold = df_high_water_threshold.set_index("feature_id")
    df_high_water_threshold = df_high_water_threshold.sort_index()

    df_streamorder = get_db_values("derived.channels_conus", ["feature_id", "strm_order"])
    df_streamorder = df_streamorder.set_index("feature_id")

    df_main = df_streamorder.join(df_high_water_threshold)

    # Setup a dictionary of empty dataframes for each of the 7 ensemble members
    print("Organizing input files / ensemble members.")
    # We're including the full 18 hour set for the ensemble members that have it, see vlab ticket for explantion.
    ensemble_hours = list(islice(cycle(hours_in_day), reference_time.hour+1, reference_time.hour+1+18))
    # This is a little complicated, but essentially slices a rolling list of hours in the day to get the
    # correct ensemble members.
    ensemble_members = list(islice(cycle(hours_in_day), (reference_time.hour+24)-6, (reference_time.hour+24)-6+7))
    for mem in ensemble_members:
        dataframes[mem] = pd.DataFrame()

    # Loop through the input files and parse out the important dates in order to organize our data processing.
    for file in a_input_files:
        matches = re.findall(r"nwm\.(\d{8})-(.*)\\nwm.t(\d{2})z.*.[f,tm](\d{2,})", file)[0]
        date = matches[0]
        year = date[:4]
        month = date[:6][-2:]
        day = date[-2:]
        ref_hour = int(matches[2])
        forecast_file = int(matches[3])
        file_ref_time = datetime.strptime(f"{year}-{month}-{day} {ref_hour}:00:00", '%Y-%m-%d %H:%M:%S')

        # Analysis metrics refer the UTC hour we are aligning between ensemble members
        # This isn't all really necessary, but I'm leaving it in here because it can be a really helpful
        # table to visualize the ensemble members and hour shift.
        analysis_time = file_ref_time + timedelta(hours=forecast_file)
        analysis_timestep = (analysis_time - reference_time)
        analysis_hour = analysis_time.hour
        if (analysis_timestep.total_seconds()/3600) <= 6:
            time_cat = '1_6'
        elif (analysis_timestep.total_seconds()/3600) > 6:
            time_cat = '7_12'

        # Append the relevant metadata for each datasource to a dictionary
        files[file] = {
            "ref_date": date, "ref_hour": ref_hour, "forecast_file": forecast_file, "forecast_day": day,
            "analysis_hour": analysis_hour, "analysis_time": analysis_time, "analysis_timestep": analysis_timestep,
            "time_cat": time_cat
        }

    # Create a sorted dataframe of the input files, eliminating all the datasets that aren't an ensemble member
    # Look at this dataframe to understand all the files that are being used!
    df_all_input_files = pd.DataFrame(files).T
    df_all_input_files = df_all_input_files[df_all_input_files["analysis_hour"].isin(ensemble_hours)]
    df_all_input_files = df_all_input_files.sort_values(["ref_date", "ref_hour", "forecast_file"], ascending=False)
    df_all_input_files = df_all_input_files.reset_index()

    # Loop through each dataset and import the NetCDF data
    # then add the data to the appropriate reference-time dataframe in our dataframes dictionary.
    print("Importing ensemble members into dataframes dictionary.")
    for row in df_all_input_files.itertuples():
        drop_vars = ['crs', 'nudge', 'velocity', 'qSfcLatRunoff', 'qBucket', 'qBtmVertRunoff']
        with xr.open_dataset(row.index, drop_variables=drop_vars) as ds:
            ds['streamflow'] = ds['streamflow']*CFS_FROM_CMS
            df_file = ds.to_dataframe().reset_index().set_index('feature_id')
            df_file = df_file.rename(columns={"streamflow": row.analysis_hour})
        df_file.drop(columns=['reference_time', 'time'], inplace=True, axis=1)
        dataframes[row.ref_hour] = df_file.join(dataframes[row.ref_hour], on='feature_id')

    # Loop through ensemble data frames and note reaches that meet rapid onset conditions within the 12-hour window.
    print(f"Identifying reaches that meet rapid onset criteria ({percent_change_threshold}% increase and high flow threshold "
          f"within {high_water_hour_threshold} hours) in each ensemble member.")
    df_all = df_main
    # Filter out Stream Orders over threshold
    # This could be moved up higher for improved performance... but leaving it here for now ####
    df_all = df_all[df_all['strm_order'] <= stream_reaches_at_or_below]
    ref_hours = []
    for ensemble in dataframes:
        df = dataframes[ensemble].join(df_main, on='feature_id')
        # Filter out Stream Orders over threshold
        # This could be moved up higher for improved performance... but leaving it here for now ####
        df = df[df['strm_order'] <= stream_reaches_at_or_below]
        df['double_increase'] = None
        df['double_hour'] = None
        df['time_cat'] = None
        df['high_water_hour'] = None
        df['rapid_onset'] = 0
        for i, hour in enumerate(ensemble_hours[1:]):  # Start on the second hour
            if hour not in df:  # Skip to the next iteration if the hour is out of range
                continue
            df['double_increase'] = np.where(((df[hour] >= (df[ensemble_hours[i]]*(1+(percent_change_threshold/100)))) & (df[hour] != 0)), 'Yes', df['double_increase'])  # Identify reaches that have an increase of 100%+  # noqa: E501
            df['double_hour'] = np.where((df['double_hour'].isnull() & (df[hour] >= (df[ensemble_hours[i]]*(1+(percent_change_threshold/100)))) & (df[hour] != 0)), hour, df['double_hour'])  # Identify the hour of the 100%+ increase  # noqa: E501
            df['time_cat'] = np.where(df['double_hour'].isin(ensemble_hours[:6]), "1_6", df['time_cat'])  # Add the time category of the 100% increase  # noqa: E501
            df['time_cat'] = np.where(df['double_hour'].isin(ensemble_hours[6:12]), "7_12", df['time_cat'])  # we're capping the double hour criteria at hour 12, but continuing to look for high flow threshold below.  # noqa: E501
            df['high_water_hour'] = np.where((df['high_water_hour'].isnull() & df['time_cat'].notnull() & (df["high_water_threshold"] > 0) & (df[hour] >= df["high_water_threshold"])), hour, df['high_water_hour'])  # Identify the hour of high flow threshold conditions  # noqa: E501
            df['rapid_onset'] = np.where((df['high_water_hour'].apply(lambda x: ensemble_hours.index(x) if x is not None else None) - df['double_hour'].apply(lambda x: ensemble_hours.index(x) if x is not None else None)) <= high_water_hour_threshold,  # noqa: E501
                                         df['time_cat'],  # Assign the time category if rapid onset conditions are met.
                                         df['rapid_onset'])  # Leave alone if conditions are not met.
        df_ensemble = df.filter(items=['rapid_onset']).rename(columns={"rapid_onset": ensemble})  # Rename the column
        ref_hours.append(ensemble)  # Create a list of the reference hours used
        df_all = df_ensemble.join(df_all, on='feature_id')  # Add each ensemble dataframe to df_all as it's calculated.

    # Calculate rapid onset flooding probability across ensemble members
    # These are the percentage values that we're going for.
    print("Consolidating and exporting data array.")
    df_all['rapid_onset_prob_all'] = ((df_all[df_all[ref_hours] != 0].count(axis=1) / len(ref_hours)) * 100).astype(int)  # noqa: E501
    df_all['rapid_onset_prob_1_6'] = ((df_all[df_all[ref_hours] == "1_6"].count(axis=1) / len(ref_hours)) * 100).astype(int)  # noqa: E501
    df_all['rapid_onset_prob_7_12'] = ((df_all[df_all[ref_hours] == "7_12"].count(axis=1) / len(ref_hours)) * 100).astype(int)  # noqa: E501

    # Format and return an array
    df_out = df_all[df_all['rapid_onset_prob_all'] != 0].reset_index()
    return df_out[["feature_id", "rapid_onset_prob_all", "rapid_onset_prob_1_6", "rapid_onset_prob_7_12"]]


def mrf_rapid_onset_probability(a_event_time, a_input_files, percent_change_threshold=100, high_water_hour_threshold=6,
                                stream_reaches_at_or_below=4):
    """
    This function takes the past current and past 6 SRF forecasts and uses them as ensemble members to calculate
    SRF Rapid Onset Flooding Probability.

    Args:
        a_event_time(datetime): Reference time
        a_input_files(list): List of input files
        percent_change_threshold (int): Number representing the percent change threshold for rapid onset criteria.
        high_water_hour_threshold (int): The number of hours that can pass within percent change threshold and high flow threshold
            conditions to be considered rapid onset.
        stream_reaches_at_or_below (int): The stream order threshold by which to consider reaches.
    """
    reference_time = a_event_time  # datetime.strptime(a_event_time, '%Y-%m-%dT%H:%M:%SZ')
    files = {}
    dataframes = {}

    df_high_water_threshold = get_db_values("derived.recurrence_flows_conus", ["feature_id", "high_water_threshold"])
    df_high_water_threshold = df_high_water_threshold.set_index("feature_id")
    df_high_water_threshold = df_high_water_threshold.sort_index()

    df_streamorder = get_db_values("derived.channels_conus", ["feature_id", "strm_order"])
    df_streamorder = df_streamorder.set_index("feature_id")

    df_main = df_streamorder.join(df_high_water_threshold)

    # Setup a dictionary of empty dataframes for each of the 7 ensemble members
    print("Organizing input files / ensemble members.")
    # ensemble_hours = list(islice(cycle(hours_in_day), reference_time.hour+1, reference_time.hour+1+270, 3))
    ensemble_members = []
    for file in a_input_files:  # finds the number of ensemble members on-the-fly
        ensemble_pattern = re.search(r'channel_rt_(\d+)', file).group(1)
        if(ensemble_pattern):
            member = int(ensemble_pattern)
            if member not in ensemble_members:
                ensemble_members.append(member)
            
    forecast_times = [reference_time + timedelta(hours=x) for x in range(3, 120, 3)]  # "Double check this!!!!
    for mem in ensemble_members:
        dataframes[mem] = pd.DataFrame()

    # Loop through the input files and parse out the important dates in order to organize our data processing.
    for file in a_input_files:
        matches = re.findall(r"nwm\.(\d{8})-(.*)\\nwm.t(\d{2})z.*.[f,tm](\d{2,})", file)[0]
        date = matches[0]
        ensemble_member = int(matches[1][-1:])
        year = date[:4]
        month = date[:6][-2:]
        day = date[-2:]
        ref_hour = int(matches[2])
        forecast_file = int(matches[3])
        file_ref_time = datetime.strptime(f"{year}-{month}-{day} {ref_hour}:00:00", '%Y-%m-%d %H:%M:%S')

        # Analysis metrics refer the UTC hour we are aligning between ensemble members
        # This isn't all really necessary, but I'm leaving it in here because it can be a really helpful
        # table to visualize the ensemble members and hour shift.
        analysis_time = file_ref_time + timedelta(hours=forecast_file)
        analysis_timestep = (analysis_time - reference_time)
        analysis_hour = analysis_time.hour

        if forecast_file <= 24:
            time_cat = 'Day1'
        elif forecast_file > 24 and forecast_file <= 48:
            time_cat = 'Day2'
        elif forecast_file > 48 and forecast_file <= 72:
            time_cat = 'Day3'
        elif forecast_file > 72 and forecast_file <= 120:
            time_cat = 'Day4-5'

        # Append the relevant metadata for each datasource to a dictionary
        files[file] = {
            "ensemble_member": ensemble_member, "forecast_file": forecast_file, "analysis_hour": analysis_hour,
            "analysis_time": analysis_time, "analysis_timestep": analysis_timestep, "time_cat": time_cat
        }

    # Create a sorted dataframe of the input files, eliminating all the datasets that aren't an ensemble member
    # Look at this dataframe to understand all the files that are being used!
    df_all_input_files = pd.DataFrame(files).T
    df_all_input_files = df_all_input_files[df_all_input_files["analysis_time"].isin(forecast_times)]
    df_all_input_files = df_all_input_files.sort_values(["ensemble_member", "forecast_file"], ascending=True)
    df_all_input_files = df_all_input_files.reset_index()

    def preprocess(ds):
        ds['streamflow'] = ds['streamflow']*CFS_FROM_CMS
        analysis_time = str(ds.time.values[0]).split(".")[0].replace("T", " ")
        analysis_time = datetime.strptime(analysis_time, "%Y-%m-%d %H:%M:%S")
        ds = ds.rename({'streamflow': analysis_time})
        ds = ds.drop_dims(['time', 'reference_time'])
        return ds

    drop_vars = ['crs', 'nudge', 'velocity', 'qSfcLatRunoff', 'qBucket', 'qBtmVertRunoff']

    # Loop through ensemble data frames and note reaches that meet rapid onset conditions within the 12-hour window.
    print(f"Identifying reaches that meet rapid onset criteria ({percent_change_threshold}% increase and high flow threshold "
          f"within {high_water_hour_threshold} hours) in each ensemble member.")
    df_all = df_main

    ensembles_used = []
    for ensemble in ensemble_members:
        print(f"Processing ensemble {ensemble}")
        df_ensemble = df_all_input_files[df_all_input_files['ensemble_member']==ensemble]  # Get ensemble specific metadata
        df_ensemble = xr.open_mfdataset(df_ensemble['index'].values.tolist(), drop_variables=drop_vars, parallel=True, preprocess=preprocess).to_dataframe()  # Use dask to open up all ensemble files at once and change streamflow col to datetime
        df_ensemble = df_ensemble.loc[(df_ensemble!=0).any(axis=1)]  # Remove all rows with a 0 value for every timestep
        df = df_ensemble.join(df_main)  # Join main data to ensemble data
        df = df[df['strm_order'] <= stream_reaches_at_or_below]  # Only look at lower order streams
        df = df[df["high_water_threshold"] > 0]  # Only look at reaches with high water threshold above 0

        df['double_increase'] = None
        df['double_hour'] = None
        df['time_cat'] = None
        df['high_water_hour'] = None
        df['rapid_onset'] = 0
        for i, forecast_time in enumerate(forecast_times[1:]):  # Start on the second hour
            if forecast_time not in df:  # Skip to the next iteration if the hour is out of range
                continue

            # Identify the hour of the 100%+ increase
            double_increase_condition = (df['high_water_hour'].isnull()) & (df[forecast_time] >= (df[forecast_times[i]]*(1+(percent_change_threshold/100)))) & (df[forecast_time] != 0)
            df_doubled = df[double_increase_condition]

            # Checking if high water occurs in the next 6 hours (assuming 3 hour timesteps). If so, set high water hour accordingly
            high_water_condition = (df_doubled[forecast_time]>=df_doubled['high_water_threshold'])
            if len(df_doubled[high_water_condition]):
                df_doubled.loc[high_water_condition, 'high_water_hour'] = forecast_time  # Identify the hour of high flow threshold conditions
                df_doubled.loc[high_water_condition, 'double_increase'] = "Yes"
                df_doubled.loc[high_water_condition, 'double_hour'] = forecast_time
            
            if forecast_time not in forecast_times[-1:]:
                high_water_condition = (df_doubled['high_water_hour'].isnull()) & (df_doubled[forecast_times[i+2]]>=df_doubled['high_water_threshold'])
                if len(df_doubled[high_water_condition]):
                    df_doubled.loc[high_water_condition, 'high_water_hour'] = forecast_times[i+2]  # Identify the hour of high flow threshold conditions
                    df_doubled.loc[high_water_condition, 'double_increase'] = "Yes"
                    df_doubled.loc[high_water_condition, 'double_hour'] = forecast_time

            if forecast_time not in forecast_times[-2:]:
                high_water_condition = (df_doubled['high_water_hour'].isnull()) & (df_doubled[forecast_times[i+3]]>=df_doubled['high_water_threshold'])
                if len(df_doubled[high_water_condition]):
                    df_doubled.loc[high_water_condition, 'high_water_hour'] = forecast_times[i+3]  # Identify the hour of high flow threshold conditions
                    df_doubled.loc[high_water_condition, 'double_increase'] = "Yes"
                    df_doubled.loc[high_water_condition, 'double_hour'] = forecast_time

            df_doubled['time_cat'] = np.where(df_doubled['double_hour'].isin(forecast_times[:24]), "Day1", df_doubled['time_cat'])  # Add the time category of the 100% increase  # noqa: E501
            df_doubled['time_cat'] = np.where(df_doubled['double_hour'].isin(forecast_times[24:48]), "Day2", df_doubled['time_cat'])  # we're capping the double hour criteria at hour 12, but continuing to look for high flow threshold below.  # noqa: E501
            df_doubled['time_cat'] = np.where(df_doubled['double_hour'].isin(forecast_times[48:72]), "Day3", df_doubled['time_cat'])  # we're capping the double hour criteria at hour 12, but continuing to look for high flow threshold below.  # noqa: E501
            df_doubled['time_cat'] = np.where(df_doubled['double_hour'].isin(forecast_times[72:120]), "Day4-5", df_doubled['time_cat'])  # we're capping the double hour criteria at hour 12, but continuing to look for high flow threshold below.  # noqa: E501

            df.update(df_doubled)
            
        df = df[~df['double_hour'].isnull() & ~df['high_water_hour'].isnull()]  # Remove rows where rapid onset flooding wont occur
        df['rapid_onset'] = df['time_cat']

        # Rename the rapid onset column to the ensemble reference hour
        df_ensemble = df.filter(items=['rapid_onset']).rename(columns={"rapid_onset": ensemble})
        ensembles_used.append(ensemble)  # Create a list of the reference hours used
        df_all = df_all.join(df_ensemble, on='feature_id')  # Add each ensemble dataframe to df_all as it's calculated.

    # Calculate rapid onset flooding probability across ensemble members
    # These are the percentage values that we're going for.
    print("Consolidating and exporting data array.")
    df_all['rapid_onset_prob_all'] = ((df_all[df_all[ensembles_used].notna()].count(axis=1) / len(ensembles_used)) * 100).astype(int)  # noqa: E501
    df_all = df_all[df_all['rapid_onset_prob_all'] != 0].reset_index()
    df_all['rapid_onset_prob_day1'] = ((df_all[df_all[ensembles_used] == "Day1"].count(axis=1) / len(ensembles_used)) * 100).astype(int)  # noqa: E501
    df_all['rapid_onset_prob_day2'] = ((df_all[df_all[ensembles_used] == "Day2"].count(axis=1) / len(ensembles_used)) * 100).astype(int)  # noqa: E501
    df_all['rapid_onset_prob_day3'] = ((df_all[df_all[ensembles_used] == "Day3"].count(axis=1) / len(ensembles_used)) * 100).astype(int)  # noqa: E501
    df_all['rapid_onset_prob_day4_5'] = ((df_all[df_all[ensembles_used] == "Day4_5"].count(axis=1) / len(ensembles_used)) * 100).astype(int)  # noqa: E501

    # Format and return an array
    return df_all[["feature_id", "rapid_onset_prob_all", "rapid_onset_prob_day1", "rapid_onset_prob_day2", "rapid_onset_prob_day3", "rapid_onset_prob_day4_5"]]  # noqa: E501
