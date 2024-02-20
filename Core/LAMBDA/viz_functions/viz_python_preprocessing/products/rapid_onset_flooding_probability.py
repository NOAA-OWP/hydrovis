"""
NWM Rapid Onset Flooding Probability Forecast
"""
import pandas as pd
import numpy as np
import xarray as xr
import re
import os
import boto3
import tempfile
from datetime import datetime, timedelta
from itertools import cycle, islice

from viz_lambda_shared_funcs import get_db_values, organize_input_files

CFS_FROM_CMS = 35.315
pd.options.mode.chained_assignment = None

def run_rapid_onset_flooding_probability(reference_time, fileset_bucket, fileset, output_file_bucket, output_file):
    percent_change_threshold = 100
    high_water_hour_threshold = 6
    stream_reaches_at_or_below = 4
    
    print("Downloading NWM Data")
    input_files = organize_input_files(fileset_bucket, fileset, download_subfolder=reference_time.strftime('%Y%m%d'))
    
    #Get NWM version from first file
    with xr.open_dataset(input_files[0]) as first_file:
        nwm_vers = first_file.NWM_version_number.replace("v","")
    
    print("Processing Files")
    ##### Short Range Configuration #####
    if "short_range" in input_files[0]:        
        df_rofp = srf_rapid_onset_probability(reference_time, input_files, percent_change_threshold, high_water_hour_threshold, stream_reaches_at_or_below)
    
    ##### Medium Range Configuration #####
    elif "medium_range" in input_files[0]:
        df_rofp = mrf_rapid_onset_probability(reference_time, input_files, percent_change_threshold, high_water_hour_threshold, stream_reaches_at_or_below)

    df_rofp['nwm_vers'] = nwm_vers
    s3 = boto3.client('s3')
    tempdir = tempfile.mkdtemp()
    tmp_ouput_path = os.path.join(tempdir, f"temp_output.csv")
    df_rofp.to_csv(tmp_ouput_path, index=False)
    s3.upload_file(tmp_ouput_path, output_file_bucket, output_file)
    os.remove(tmp_ouput_path)

def srf_rapid_onset_probability(reference_time, a_input_files, percent_change_threshold=100, high_water_hour_threshold=6,
                                stream_reaches_at_or_below=4):
    """
    This function takes the past current and past 6 SRF forecasts and uses them as ensemble members to calculate
    SRF Rapid Onset Flooding Probability.

    Args:
        reference_time(datetime): Reference time
        a_input_files(list): List of input files
        percent_change_threshold (int): Number representing the percent change threshold for rapid onset criteria.
        high_water_hour_threshold (int): The number of hours that can pass within percent change threshold and high flow threshold
            conditions to be considered rapid onset.
        stream_reaches_at_or_below (int): The stream order threshold by which to consider reaches.
    """
    reference_time = reference_time  # datetime.strptime(reference_time, '%Y-%m-%dT%H:%M:%SZ')
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
        matches = re.findall(r"(\d{4})(\d{2})(\d{2})/nwm.t(\d{2})z.*.[f,tm](\d{2,})", file)[0]
        model_initialization_year = matches[0]
        model_initialization_month = matches[1]
        model_initialization_day = matches[2]
        model_initialization_date = f"{model_initialization_year}{model_initialization_month}{model_initialization_day}"
        model_initialization_hour = int(matches[3])
        model_initialization_time = datetime.strptime(f"{model_initialization_year}-{model_initialization_month}-{model_initialization_day} {model_initialization_hour}:00:00", '%Y-%m-%d %H:%M:%S')
        model_output_delta_hour = int(matches[4])

        # Analysis metrics refer the UTC hour we are aligning between ensemble members
        # This isn't all really necessary, but I'm leaving it in here because it can be a really helpful
        # table to visualize the ensemble members and hour shift.
        model_output_valid_time = model_initialization_time + timedelta(hours=model_output_delta_hour)
        
        if model_output_valid_time <= reference_time or model_output_valid_time > reference_time + timedelta(hours=12):
            continue
        
        model_output_valid_hour = model_output_valid_time.hour
        model_output_delta_time = (model_output_valid_time - reference_time)

        if (model_output_delta_time.total_seconds()/3600) <= 6:
            model_output_delta_time_cat = '1_6'
        elif (model_output_delta_time.total_seconds()/3600) > 6:
            model_output_delta_time_cat = '7_12'

        # Append the relevant metadata for each datasource to a dictionary
        files[file] = {
            "model_initialization_date": model_initialization_date, "model_initialization_hour": model_initialization_hour, 
            "model_output_delta_hour": model_output_delta_hour, "model_initialization_day": model_initialization_day,
            "model_output_valid_hour": model_output_valid_hour, "model_output_valid_time": model_output_valid_time, 
            "model_output_delta_time": model_output_delta_time, "model_output_delta_time_cat": model_output_delta_time_cat
        }

    # Create a sorted dataframe of the input files, eliminating all the datasets that aren't an ensemble member
    # Look at this dataframe to understand all the files that are being used!
    df_all_input_files = pd.DataFrame(files).T
    df_all_input_files = df_all_input_files.sort_values(["model_initialization_date", "model_initialization_hour", "model_output_delta_hour"])
    df_all_input_files = df_all_input_files.reset_index()

    def preprocess(ds):
        ds['streamflow'] = ds['streamflow']*CFS_FROM_CMS
        analysis_time = str(ds.time.values[0]).split(".")[0].replace("T", " ")
        analysis_time = datetime.strptime(analysis_time, "%Y-%m-%d %H:%M:%S")
        ds = ds.rename({'streamflow': analysis_time.hour})
        ds = ds.drop_dims(['time', 'reference_time'])
        return ds

    drop_vars = ['crs', 'nudge', 'velocity', 'qSfcLatRunoff', 'qBucket', 'qBtmVertRunoff']

    # Loop through ref_hour data frames and note reaches that meet rapid onset conditions within the 12-hour window.
    print(f"Identifying reaches that meet rapid onset criteria ({percent_change_threshold}% increase and high flow threshold "
          f"within {high_water_hour_threshold} hours) in each ref_hour member.")
    df_all = df_main
    ensembles_used = []
    for model_initialization_hour, df_model_initialization_hour in df_all_input_files.groupby("model_initialization_hour"):
        print(f"Processing model_initialization_hour {model_initialization_hour}")
        model_output_valid_hours = df_model_initialization_hour['model_output_valid_hour'].values

        df_ensemble = xr.open_mfdataset(df_model_initialization_hour['index'].values.tolist(), drop_variables=drop_vars, preprocess=preprocess, combine='by_coords').to_dataframe()  # Use dask to open up all ensemble files at once and change streamflow col to datetime
        df_ensemble = df_ensemble[model_output_valid_hours]
        df_ensemble = df_ensemble.loc[(df_ensemble!=0).any(axis=1)]  # Remove all rows with a 0 value for every timestep
        df = df_ensemble.join(df_main)  # Join main data to ref_hour data
        df = df[df['strm_order'] <= stream_reaches_at_or_below]  # Only look at lower order streams
        df = df[df["high_water_threshold"] > 0]  # Only look at reaches with high water threshold above 0

        df['double_increase'] = None
        df['high_water_hour'] = None
        df['in_rof'] = False
        df['hour_1_6_rof'] = False
        df['hour_7_12_rof'] = False
        previous_hour_rof = None

        for i, model_output_valid_hour in enumerate(model_output_valid_hours[1:]):  # Start on the second hour

            
            if model_output_valid_hour not in df:  # Skip to the next iteration if the hour is out of range
                continue

            if model_output_valid_hour in model_output_valid_hours[:6]:
                hour_rof = 'hour_1_6_rof'
            else:
                hour_rof = 'hour_7_12_rof'

            if not previous_hour_rof:
                previous_hour_rof = hour_rof

            # Identify reaches currently in ROF and ending because of drop of flow
            rof_ending_condition = (df['in_rof']==True) & (df[model_output_valid_hour] < df['high_water_threshold']) & (df['high_water_hour'] < model_output_valid_hour)
            df.loc[rof_ending_condition, hour_rof] = True
            df.loc[rof_ending_condition, 'high_water_hour'] = None
            df.loc[rof_ending_condition, 'in_rof'] = False

            # Identify reaches currently in ROF and set ROF status to True. Will cover reaches in ROF over multiple days
            rof_continous_condition = (df['in_rof']==True)
            if previous_hour_rof != hour_rof:
                df.loc[rof_continous_condition, hour_rof] = True

            # Identify the hour of the 100%+ increase
            double_increase_condition = (df[hour_rof]==False) & (df[model_output_valid_hour] >= (df[model_output_valid_hours[i]]*(1+(percent_change_threshold/100)))) & (df[model_output_valid_hour] != 0)
            df_doubled = df[double_increase_condition]

            # Checking if high water occurs in the next 6 hours (assuming 3 hour timesteps). If so, set high water hour accordingly
            high_water_condition = (df_doubled[model_output_valid_hour]>=df_doubled['high_water_threshold'])
            if len(df_doubled[high_water_condition]):
                df_doubled.loc[high_water_condition, 'high_water_hour'] = model_output_valid_hour  # Identify the hour of high flow threshold conditions
                df_doubled.loc[high_water_condition, 'in_rof'] = True
                df_doubled.loc[high_water_condition, hour_rof] = True
            
            if model_output_valid_hour not in model_output_valid_hours[-1:]:
                high_water_condition = (df_doubled[model_output_valid_hours[i+2]]>=df_doubled['high_water_threshold'])
                if len(df_doubled[high_water_condition]):
                    df_doubled.loc[high_water_condition, 'high_water_hour'] = model_output_valid_hours[i+2]  # Identify the hour of high flow threshold conditions
                    df_doubled.loc[high_water_condition, 'in_rof'] = True
                    df_doubled.loc[high_water_condition, hour_rof] = True

            if model_output_valid_hour not in model_output_valid_hours[-2:]:
                high_water_condition = (df_doubled[model_output_valid_hours[i+3]]>=df_doubled['high_water_threshold'])
                if len(df_doubled[high_water_condition]):
                    df_doubled.loc[high_water_condition, 'high_water_hour'] = model_output_valid_hours[i+3]  # Identify the hour of high flow threshold conditions
                    df_doubled.loc[high_water_condition, 'in_rof'] = True
                    df_doubled.loc[high_water_condition, hour_rof] = True

            df.update(df_doubled)

        df = df[df['hour_1_6_rof'] | df['hour_7_12_rof']]  # Remove rows where rapid onset flooding wont occur

        # Rename the rapid onset column to the ensemble reference hour
        df_ensemble = df.filter(items=['hour_1_6_rof', 'hour_7_12_rof'])
        df_ensemble = df_ensemble.rename(columns={
            "hour_1_6_rof": f"hour_1_6_rof_{model_initialization_hour}",
            "hour_7_12_rof": f"hour_7_12_rof_{model_initialization_hour}"
        })
        ensembles_used.append(model_initialization_hour)  # Create a list of the reference hours used
        df_all = df_all.join(df_ensemble, on='feature_id')  # Add each ensemble dataframe to df_all as it's calculated.
    
    # Calculate rapid onset flooding probability across ensemble members
    # These are the percentage values that we're going for.
    print("Consolidating and exporting data array.")
    df_all = df_all.drop(columns=['strm_order', 'high_water_threshold'])
    df_all = df_all.replace(False, np.nan)
    df_all = df_all.dropna(how="all")

    hour_1_6_ensembles = [f"hour_1_6_rof_{ensemble}" for ensemble in ensembles_used]
    hour_7_12_ensembles = [f"hour_7_12_rof_{ensemble}" for ensemble in ensembles_used]
    all_enembles_used = hour_1_6_ensembles + hour_7_12_ensembles

    df_all['rapid_onset_prob_all'] = ((df_all[all_enembles_used].count(axis=1) / len(all_enembles_used)) * 100).astype(int)
    df_all['rapid_onset_prob_1_6'] = ((df_all[hour_1_6_ensembles].count(axis=1) / len(ensembles_used)) * 100).astype(int)  # noqa: E501
    df_all['rapid_onset_prob_7_12'] = ((df_all[hour_7_12_ensembles].count(axis=1) / len(ensembles_used)) * 100).astype(int)  # noqa: E501
    df_all = df_all.reset_index()

    return df_all[["feature_id", "rapid_onset_prob_all", "rapid_onset_prob_1_6", "rapid_onset_prob_7_12"]]


def mrf_rapid_onset_probability(reference_time, a_input_files, percent_change_threshold=100, high_water_hour_threshold=6,
                                stream_reaches_at_or_below=4):
    """
    This function takes the past current and past 6 SRF forecasts and uses them as ensemble members to calculate
    SRF Rapid Onset Flooding Probability.

    Args:
        reference_time(datetime): Reference time
        a_input_files(list): List of input files
        percent_change_threshold (int): Number representing the percent change threshold for rapid onset criteria.
        high_water_hour_threshold (int): The number of hours that can pass within percent change threshold and high flow threshold
            conditions to be considered rapid onset.
        stream_reaches_at_or_below (int): The stream order threshold by which to consider reaches.
    """
    reference_time = reference_time  # datetime.strptime(reference_time, '%Y-%m-%dT%H:%M:%SZ')
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
        matches = re.findall(r"(\d{8})/nwm.t(\d{2})z.medium_range.channel_rt_(\d{1}).[f,tm](\d{2,})", file)[0]
        date = matches[0]
        year = date[:4]
        month = date[:6][-2:]
        day = date[-2:]
        ref_hour = int(matches[1])
        ensemble_member = int(matches[2])
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
        df_ensemble = xr.open_mfdataset(df_ensemble['index'].values.tolist(), drop_variables=drop_vars, preprocess=preprocess, combine='by_coords').to_dataframe()  # Use dask to open up all ensemble files at once and change streamflow col to datetime
        df_ensemble = df_ensemble.loc[(df_ensemble!=0).any(axis=1)]  # Remove all rows with a 0 value for every timestep
        df = df_ensemble.join(df_main)  # Join main data to ensemble data
        df = df[df['strm_order'] <= stream_reaches_at_or_below]  # Only look at lower order streams
        df = df[df["high_water_threshold"] > 0]  # Only look at reaches with high water threshold above 0

        df['double_increase'] = None
        df['high_water_hour'] = None
        df['in_rof'] = False
        df['day1_rof'] = False
        df['day2_rof'] = False
        df['day3_rof'] = False
        df['day4_rof'] = False
        df['day5_rof'] = False
        previous_day_rof = None

        for i, forecast_time in enumerate(forecast_times[1:]): #start at second hour, then i is the timestep before when using list
            if forecast_time not in df:  # Skip to the next iteration if the hour is out of range
                continue

            if forecast_time <= reference_time + timedelta(days=1):
                day_rof = 'day1_rof'
            elif forecast_time <= reference_time + timedelta(days=2):
                day_rof = 'day2_rof'
            elif forecast_time <= reference_time + timedelta(days=3):
                day_rof = 'day3_rof'
            elif forecast_time <= reference_time + timedelta(days=4):
                day_rof = 'day4_rof'
            else:
                day_rof = 'day5_rof'

            if not previous_day_rof:
                previous_day_rof = day_rof

            # Identify reaches currently in ROF and ending because of drop of flow
            rof_ending_condition = (df['in_rof']==True) & (df[forecast_time] < df['high_water_threshold']) & (df['high_water_hour'] < forecast_time)
            df.loc[rof_ending_condition, day_rof] = True
            df.loc[rof_ending_condition, 'high_water_hour'] = None
            df.loc[rof_ending_condition, 'in_rof'] = False

            # Identify reaches currently in ROF and set ROF status to True. Will cover reaches in ROF over multiple days
            rof_continous_condition = (df['in_rof']==True)
            if previous_day_rof != day_rof:
                df.loc[rof_continous_condition, day_rof] = True

            # Identify the hour of the 100%+ increase
            double_increase_condition = (df[day_rof]==False) & (df[forecast_time] >= (df[forecast_times[i]]*(1+(percent_change_threshold/100)))) & (df[forecast_time] != 0)
            df_doubled = df[double_increase_condition]

            # Checking if high water occurs in the next 6 hours (assuming 3 hour timesteps). If so, set high water hour accordingly
            high_water_condition = (df_doubled[forecast_time]>=df_doubled['high_water_threshold'])
            if len(df_doubled[high_water_condition]):
                df_doubled.loc[high_water_condition, 'high_water_hour'] = forecast_time  # Identify the hour of high flow threshold conditions
                df_doubled.loc[high_water_condition, 'in_rof'] = True
                df_doubled.loc[high_water_condition, day_rof] = True
            
            if forecast_time not in forecast_times[-1:]:
                high_water_condition = (df_doubled[forecast_times[i+2]]>=df_doubled['high_water_threshold'])
                if len(df_doubled[high_water_condition]):
                    df_doubled.loc[high_water_condition, 'high_water_hour'] = forecast_times[i+2]  # Identify the hour of high flow threshold conditions
                    df_doubled.loc[high_water_condition, 'in_rof'] = True
                    df_doubled.loc[high_water_condition, day_rof] = True

            if forecast_time not in forecast_times[-2:]:
                high_water_condition = (df_doubled[forecast_times[i+3]]>=df_doubled['high_water_threshold'])
                if len(df_doubled[high_water_condition]):
                    df_doubled.loc[high_water_condition, 'high_water_hour'] = forecast_times[i+3]  # Identify the hour of high flow threshold conditions
                    df_doubled.loc[high_water_condition, 'in_rof'] = True
                    df_doubled.loc[high_water_condition, day_rof] = True

            df.update(df_doubled)

        df = df[df['day1_rof'] | df['day2_rof'] | df['day3_rof'] | df['day4_rof'] | df['day5_rof']]  # Remove rows where rapid onset flooding wont occur

        # Rename the rapid onset column to the ensemble reference hour
        df_ensemble = df.filter(items=['day1_rof', 'day2_rof', 'day3_rof', 'day4_rof','day5_rof'])
        df_ensemble = df_ensemble.rename(columns={
            "day1_rof": f"day1_rof_{ensemble}",
            "day2_rof": f"day2_rof_{ensemble}",
            "day3_rof": f"day3_rof_{ensemble}",
            "day4_rof": f"day4_rof_{ensemble}",
            "day5_rof": f"day5_rof_{ensemble}"
        })
        ensembles_used.append(ensemble)  # Create a list of the reference hours used
        df_all = df_all.join(df_ensemble, on='feature_id')  # Add each ensemble dataframe to df_all as it's calculated.
        
    # Calculate rapid onset flooding probability across ensemble members
    # These are the percentage values that we're going for.
    print("Consolidating and exporting data array.")
    df_all = df_all.drop(columns=['strm_order', 'high_water_threshold'])
    df_all = df_all.replace(False, np.nan)
    df_all = df_all.dropna(how="all")

    day1_ensembles = [f"day1_rof_{ensemble}" for ensemble in ensembles_used]
    day2_ensembles = [f"day2_rof_{ensemble}" for ensemble in ensembles_used]
    day3_ensembles = [f"day3_rof_{ensemble}" for ensemble in ensembles_used]
    day4_ensembles = [f"day4_rof_{ensemble}" for ensemble in ensembles_used]
    day5_ensembles = [f"day5_rof_{ensemble}" for ensemble in ensembles_used]
    days45_ensembles = day4_ensembles + day5_ensembles
    all_enembles_used = day1_ensembles + day2_ensembles + day3_ensembles + day4_ensembles + day5_ensembles

    df_all['rapid_onset_prob_all'] = ((df_all[all_enembles_used].count(axis=1) / len(all_enembles_used)) * 100).astype(int)
    df_all['rapid_onset_prob_day1'] = ((df_all[day1_ensembles].count(axis=1) / len(ensembles_used)) * 100).astype(int)  # noqa: E501
    df_all['rapid_onset_prob_day2'] = ((df_all[day2_ensembles].count(axis=1) / len(ensembles_used)) * 100).astype(int)  # noqa: E501
    df_all['rapid_onset_prob_day3'] = ((df_all[day3_ensembles].count(axis=1) / len(ensembles_used)) * 100).astype(int)  # noqa: E501
    df_all['rapid_onset_prob_day4_5'] = ((df_all[days45_ensembles].count(axis=1) / len(ensembles_used)) * 100).astype(int)  # noqa: E501
    df_all = df_all.reset_index()

    # Format and return an array
    return df_all[["feature_id", "rapid_onset_prob_all", "rapid_onset_prob_day1", "rapid_onset_prob_day2", "rapid_onset_prob_day3", "rapid_onset_prob_day4_5"]]  # noqa: E501
