import datetime as dt
import os
from netCDF4 import Dataset
import xarray
import numpy as np
import pandas as pd
import re
import boto3
import tempfile
from viz_lambda_shared_funcs import get_db_values, check_if_file_exists

def run_high_water_probability(reference_time, fileset_bucket, fileset, output_file_bucket, output_file):
    ##### Data Prep #####
    print("Downloading NWM Data")
    input_files = organize_input_files(fileset_bucket, fileset, download_subfolder=reference_time.strftime('%Y%m%d'))

    #Get NWM version from first file
    with xarray.open_dataset(input_files[0]) as first_file:
        nwm_vers = first_file.NWM_version_number.replace("v","")

    print("Retrieving High Water Values From Viz DB")
    df_high_water_threshold = get_db_values("derived.recurrence_flows_conus", ["feature_id", "high_water_threshold"])
    df_high_water_threshold = df_high_water_threshold.set_index("feature_id")
    df_high_water_threshold = df_high_water_threshold.sort_index()

    ##### Short Range Configuration #####
    if "short_range" in input_files[0]:
        lead_times = list(range(1, 13, 1))
        discard_threshold = 7
        df_probabilities = srf_high_water_probability(reference_time, lead_times, discard_threshold, input_files, df_high_water_threshold)
        df_probabilities = df_probabilities.rename(columns={"Prob": "srf_prob"})

    ##### Medium Range Configuration #####
    elif "medium_range" in input_files[0]:
        df_probabilities = pd.DataFrame()
        day_windows = {'start_hour': [3, 27, 51, 75, 3], 'end_hour': [24, 48, 72, 120, 120]}

        for i in range(len(day_windows['start_hour'])):
            day_files = []
            begin_hour = day_windows['start_hour'][i]
            end_hour = day_windows['end_hour'][i]
            print(f"Calculating probabilities for {begin_hour}_to_{end_hour}")
            for file in input_files:
                hour_pattern = re.search(r'f(\d\d\d)', file).group(1)
                if(hour_pattern):
                    hour = int(hour_pattern)
                    if(hour >= begin_hour and hour <= end_hour):
                        day_files.append(file)

            probability_df = mrf_high_water_probability(day_files, df_high_water_threshold)
            probability_df = probability_df.rename(columns={"Prob": f"hours_{begin_hour}_to_{end_hour}"})

            if df_probabilities.empty:
                df_probabilities = probability_df
            else:
                df_probabilities = df_probabilities.join(probability_df)

    ##### Format and Upload Output #####
    print("Adding high water threshold, reference time, and update time to dataframe")
    df_probabilities = df_probabilities.loc[~(df_probabilities == 0).all(axis=1)]
    df_probabilities = df_probabilities.join(df_high_water_threshold)
    df_probabilities = df_probabilities.loc[~(df_probabilities['high_water_threshold'] == 0)]
    df_probabilities['nwm_vers'] = nwm_vers
    df_probabilities = df_probabilities.reset_index()

    print("Uploading output CSV file to S3")
    s3 = boto3.client('s3')
    tempdir = tempfile.mkdtemp()
    tmp_ouput_path = os.path.join(tempdir, f"temp_output.csv")
    df_probabilities.to_csv(tmp_ouput_path, index=False)
    s3.upload_file(tmp_ouput_path, output_file_bucket, output_file)
    print(f"--- Uploaded to {output_file_bucket}:{output_file}")
    os.remove(tmp_ouput_path)

def srf_high_water_probability(reference_time, lead_times, discard_threshold, nwm_fpaths, df_high_water_threshold):
    """
    Creates the srf (12-Hour) high water threshold probability product for the reference time using the specified files.

    Args:
        reference_time (datetime.datetime): A datetime.datetime object representing the basis time of the analysis
        lead_times (list): A list of integers, each of which represents the number of hours from the reference_time to
            consider
        discard_threshold (int): An integer representing the number of hours back from the reference_time at which to
            no longer include the forecast files in the analysis.
        nwm_fpaths (list): A list of strings, each of which reprsents the path to a forecast file that is to be
            considered for the analysis.

    Old args:
        high_water_threshold_type (str): A string indicating what dataset will be used for determining high flow.
        erom_anom_threshold (int, optional): An integer used to determine the number of reaches that are visualized if
            using the erom threshold. originally set to erom_anom_threshold=4
    """

    # calculate valid time for forecast
    print("Calculating valid times...")
    valid_times = calc_valid_times(reference_time, lead_times)

    discard_date = reference_time - dt.timedelta(hours=discard_threshold)

    # return paths to all files with specified valid time
    print("Collecting files for valid times...")
    working_fpaths = find_nwm_file_paths(nwm_fpaths, valid_times, reference_time, discard_date)
    nwm_file_count = len(working_fpaths)
    print("Found {} files with matching valid times.".format(nwm_file_count))

    # Import Feature IDs
    print("-->Importing feature IDs...")
    with xarray.open_dataset(working_fpaths[0]) as ds_features:
        # Gets a dataframe of feature ids and streamflow for forecast
        streamflow_features = ds_features['streamflow'].to_dataframe()

    joined = streamflow_features.join(df_high_water_threshold)   # attaches recurrence flows to streamflow features
    recurrence_flows_array = joined["high_water_threshold"].values  # Extract recurrence flows as array
    featureID_list = joined.index.values  # Extract feature_ids as array

    # Calculate High Flow Probabilities
    print("-->Calculating high flow probabilities...")

    # Set ensemble members (nwm forecast hours) on-the-fly
    # Ensemble members for srf are represented by a forecast hour, each of the 7 hours (t-hour) up to and
    # including the reference time
    ensemble_number = discard_threshold
    ensemble_members = []
    for i in range(1, ensemble_number + 1):
        member_date = discard_date + dt.timedelta(hours=i)
        member = member_date.strftime("%H")
        ensemble_members.append(member)

    # create a NumPy array of zeros with the same length of recurrence_flows_array; this array will be used to
    # count up the number of streamflow files that predicted a reach would be above its high water threshold flow
    final_above_array = np.zeros(len(recurrence_flows_array), dtype=np.int16)
    for member in ensemble_members:
        ensemble_files_list = [x for x in working_fpaths if 'nwm.t{}z.short_range.channel_rt'.format(member) in x]
        # creates a NumPy array of zeros with the same length of recurrence_flows_array;
        # this array will be used to count up the number of streamflow files that predicted a reach would be above
        # its high water threshold flow
        above_array = np.zeros(len(recurrence_flows_array), dtype=np.int16)
        for file in ensemble_files_list:
            n = Dataset(file)
            streamflows = n['streamflow'][:]
            n.close()
            streamflows = streamflows * 35.3147  # convert streamflow from cms to cfs
            # checks to see if any streamflow values are at or above their high water threshold flow, and
            # returns a boolean array of the results
            true_false_array = np.greater_equal(streamflows, recurrence_flows_array)
            # increases the above count in above_array for reaches that had streamflow values above their high water threshold
            above_array = above_array + true_false_array
        # set anything in final_above_array >0 to 1, so -any- instance of high water threshold gives a stream reach a 1
        above_array = np.where(above_array >= 1, 1, 0)
        final_above_array += above_array  # add ensemble member's 0 or 1 predictions for each stream

    print("Processing NWM probabilities...")
    # divides above_array by the total number of streamflow files to compute probabilities, and
    # then multiplies the results by 100 to covert them into percentages
    probabilities = (final_above_array / ensemble_number) * 100.0

    df_probabilities = pd.DataFrame(list(zip(featureID_list, probabilities)), columns=['feature_id', 'Prob'])
    df_probabilities = df_probabilities.set_index('feature_id')
    df_probabilities['Prob'] = df_probabilities['Prob'].astype(int)

    return df_probabilities


def mrf_high_water_probability(streamflow_files_list, high_water_values):
    """
    This function computes high water probabilities (%) from the 7 members of the National Water Model (NWM) medium-range
    forecast.

    Args:
        streamflow_files_list (list): A list of paths to the NWM channel_rt output NetCDF files for the forecast of
            interest.

    Returns:
        probability_array (array): An array of (Feature ID, High Water Probability (%)) pairs for the time period of
            interest.
    """

    # Import Feature IDs
    print("--> Importing feature IDs...")

    with xarray.open_dataset(streamflow_files_list[0]) as ds_features:
        df_features = ds_features['streamflow'].to_dataframe()  # gets a dataframe of feature ids and streamflows
    joined = df_features.join(high_water_values)  # attaches the high water threshold flows to the streamflow features
    high_water_flows_array = joined["high_water_threshold"].values  # extracts the high water threshold flows as an array
    featureID_array = joined.index.values  # extracts the feature IDs as an array

    # Calculate High Water Probabilities
    print("--> Calculating high water probabilities...")

    ensemble_members = []
    for file in streamflow_files_list:  # finds the number of ensemble members on-the-fly
        ensemble_pattern = re.search(r'channel_rt_(\d+)', file).group(1)
        if(ensemble_pattern):
            member = int(ensemble_pattern)
            if member not in ensemble_members:
                ensemble_members.append(member)

    # creates a NumPy array of zeros with the same length of high water threshold flows_array;
    # this array will be used to count up the number of ensemble members that predicted a reach would be
    # above its high water threshold flow
    final_above_array = np.zeros(len(high_water_flows_array), dtype=np.int16)
    for member in ensemble_members:
        ensemble_files_list = [x for x in streamflow_files_list if 'channel_rt_{}'.format(member) in x]
        above_array = np.zeros(len(high_water_flows_array), dtype=np.int16)  # creates a NumPy array of zeros
        for file in ensemble_files_list:
            n = Dataset(file)
            streamflows = n['streamflow'][:]
            n.close()
            streamflows = streamflows * 35.3147  # converts streamflows from cms to cfs
            # checks to see if any streamflow values are at or above their high water threshold flow
            # returns a boolean array of the results
            true_false_array = np.greater_equal(streamflows, high_water_flows_array)
            # increases the above count in above_array for reaches that had streamflow values above their high water threshold flows
            above_array = above_array + true_false_array
        # sets anything in final_above_array >0 to 1, so -any- instance of high water threshold gives a stream reach a 1
        above_array = np.where(above_array >= 1, 1, 0)
        final_above_array += above_array  # adds the ensemble member's predictions for each stream to final_above_array

    # divides final_above_array by the total number of streamflow files to compute probabilities
    # then multiplies the results by 100 to covert them into percentages
    probabilities = (final_above_array / len(ensemble_members)) * 100.0

    df_probabilities = pd.DataFrame(list(zip(featureID_array, probabilities)), columns=['feature_id', 'Prob'])
    df_probabilities = df_probabilities.set_index('feature_id')
    df_probabilities['Prob'] = df_probabilities['Prob'].astype(int)

    return df_probabilities


def calc_valid_times(reference_time, lead_times):
    valid_times = []

    for lead_time in lead_times:
        valid_time_obj = reference_time + dt.timedelta(hours=lead_time)
        valid_time_str = valid_time_obj.strftime('%Y-%m-%d_%H:00:00')
        valid_times.append(valid_time_str)
        print("** Valid time: ", valid_time_str)
    return valid_times


def find_nwm_file_paths(nwm_fpaths, valid_times, reference_time, discard_date):
    """
    Determines which files are needed to support the probabilistic forecast for
    the specified valid time.

    Args:
        nwm_fpaths(list): a list of strings, each of which is the path to a nwm file
        valid_times(list): a list of strings, each representing a datetime

    Returns:
        A list of file paths.
    """

    working_fpaths = []
    for nwm_fpath in nwm_fpaths:
       # Extract file's date from filepath
        file_date = dt.datetime.strptime(re.search('[0-9]{8}', nwm_fpath).group(), '%Y%m%d') \
                  + dt.timedelta(hours=int(re.search('t[0-9]{2}z', nwm_fpath).group()[1:3]))

        # Exclude file if older than discard date
        if discard_date:
            if file_date <= discard_date:
                continue

        # Exclude file if it is a forecast generated later than reference_time
        if file_date > reference_time:
            continue

        # Validate that file exists
        if not os.path.exists(nwm_fpath):
            print(('WARNING - File given but not found: {0}'.format(nwm_fpath)))
            continue

        # check if NWM file falls in range of valid times
        try:
            with Dataset(nwm_fpath, 'r') as f:
                if f.model_output_valid_time in valid_times:
                    working_fpaths.append(nwm_fpath)
        except IOError:
            print(('WARNING - File given could not be opened: {0}'.format(nwm_fpath)))

    return working_fpaths

def organize_input_files(fileset_bucket, fileset, download_subfolder):
    local_files = []
    for file in fileset:
        download_path = check_if_file_exists(fileset_bucket, file, download=True, download_subfolder=download_subfolder)
        local_files.append(download_path)
    return local_files