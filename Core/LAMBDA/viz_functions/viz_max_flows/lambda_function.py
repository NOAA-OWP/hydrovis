import os
import xarray
import pandas as pd
import numpy as np
import boto3
import tempfile

from viz_lambda_shared_funcs import get_configuration, check_if_file_exists

CACHE_DAYS = os.environ['CACHE_DAYS']
MAX_PROPS = {
    'channel_rt': {
        'max_variable': 'streamflow',
        'common_var': 'flow',
        'id': 'feature_id',
        'extras': ['NWM_version_number']
    },
    'total_water': {
        'max_variable': 'elevation',
        'common_var': 'elev',
        'id': 'nSCHISM_hgrid_node',
        'extras': ['SCHISM_hgrid_node_x', 'SCHISM_hgrid_node_y']
    }
}


def lambda_handler(event, context):
    """
        The lambda handler is the function that is kicked off with the lambda. This function will take all the
        forecast steps in the NWM configuration, calculate the max streamflow for each feature and then save the
        output in S3
        Args:
            event(event object): An event is a JSON-formatted document that contains data for a Lambda function to
                                 process
            context(object): Provides methods and properties that provide information about the invocation, function,
                             and runtime environment
    """
    # parse the event to get the bucket and file that kicked off the lambda
    print("Parsing event to get configuration")
    fileset = event['map_item']['fileset']
    fileset_bucket = event['map_item']['fileset_bucket']
    output_file = event['map_item']['output_file']
    output_file_bucket = event['map_item']['output_file_bucket']
    reference_time = event['reference_time']

    print(f"Creating {output_file}")
    # Once the files exist, calculate the max flows
    aggregate_max_to_file(fileset_bucket, fileset, output_file_bucket, output_file)
    print(f"Successfully created {output_file} in {output_file_bucket}")

    print("Done")


def aggregate_max_to_file(fileset_bucket, fileset, output_file_bucket, output_file):
    """
        Iterates through a times series of National Water Model (NWM) channel_rt output NetCDF files, and finds the
        maximum flow of each NWM reach during this period.  Outputs a NetCDF file containing all NWM reaches and their
        maximum flows.
        Args:
            data_bucket (str): S3 bucket name where the NWM files are stored
            path_to_nwm_files (str or list): Path to the directory or list of the paths to the files to caclulate
                                             maximum flows on.
            output_netcdf (str): Key (path) of the max flows netcdf that will be store in S3
    """
    model_var = [d for d in list(MAX_PROPS.keys()) if d in fileset[0]][0]
    max_props = MAX_PROPS[model_var]
    common_var = max_props['common_var']
    
    print("--> Calculating flows")
    max_result = aggregate_max(fileset_bucket, fileset, max_props)  # creates a max flow array for all reaches

    print(f"--> Creating {output_file}")
    write_netcdf(max_result, output_file_bucket, output_file)  # creates the output NetCDF file


def download_file(data_bucket, file_path, download_path):
    s3 = boto3.client('s3')
    
    file_path = check_if_file_exists(data_bucket, file_path)

    try:
        s3.download_file(data_bucket, file_path, download_path)
        return True
    except Exception as e:
        print(f"File failed to download {file_path}: {e}")
        return False


def aggregate_max(fileset_bucket, fileset, max_props):
    """
        Iterates through a times series of National Water Model (NWM) channel_rt output NetCDF files, and finds
        the maximum flow of each NWM reach during this period.
        Args:
            data_bucket (str): S3 bucket name where the NWM files are stored
            active_file_paths (str or list): Path to the directory or list of the paths to the files to caclulate
                                             maximum flows on.
        Returns:
            max_flows (numpy array): Numpy array that contains all the max flows for each feature for the forecast
            feature_ids (numpy array): Numpy array that contains all the features ids for the forecast
    """
    max_var = max_props['max_variable']
    id_var = max_props['id']
    identifiers = None
    max_vals = None
    extras = None
    
    tempdir = tempfile.mkdtemp()

    for file in fileset:
        download_path = os.path.join(tempdir, os.path.basename(file))
        print(f"--> Downloading {file} to {download_path}")
        download_file(fileset_bucket, file, download_path)
        
        with xarray.open_dataset(download_path) as ds:
            temp_vals = ds[max_var].values.flatten()  # imports the values from each file
            if max_vals is None:
                max_vals = temp_vals
            if identifiers is None:
                identifiers = ds[id_var].values
            if extras is None and max_props['extras']:
                extras = []
                for extra in max_props['extras']:
                    try:
                        extras.append({
                            'varname': extra,
                            'array': ds[extra].values
                        })
                    except:
                        extras.append({
                            'varname': extra,
                            'array': ds.attrs[extra]
                        })
        os.remove(download_path)

        # compares the values in each file with those stored in the max_vals array, and keeps the
        # maximum value for each entity
        max_vals = np.maximum(max_vals, temp_vals)

    return {
        "identifiers": {"varname": id_var, "array": identifiers},
        "max_values": {"varname": max_var, "array": max_vals},
        "extras": extras
    }


def write_netcdf(max_result, output_file_bucket, output_file):
    """
        Iterates through a times series of National Water Model (NWM) channel_rt output NetCDF files, and finds the
        maximum flow of each NWM reach during this period.
        Args:
            feature_ids (numpy array): Numpy array that contains all the features ids for the forecast
            peak_flows (numpy array): Numpy array that contains all the max flows for each feature for the forecast
            output_netcdf (str or list): Key (path) of the max flows netcdf that will be store in S3
    """
    s3 = boto3.client('s3')
    tempdir = tempfile.mkdtemp()
    tmp_netcdf = os.path.join(tempdir, 'max_vals.nc')

    id_colname = max_result['identifiers']['varname']
    values_colname = max_result['max_values']['varname']
    identifiers = max_result['identifiers']['array']
    values = max_result['max_values']['array']
    extras = max_result['extras'] 

    # Create a dataframe from the identifiers and values arrays
    df = pd.DataFrame(identifiers, columns=[id_colname]).set_index(id_colname)
    df[values_colname] = values
    df[values_colname] = df[values_colname].fillna(0)
    if extras:
        for extra in extras:
            df[extra['varname']] = extra['array']

    # Save the max vals dataframe to a loacl netcdf file
    df.to_xarray().to_netcdf(tmp_netcdf)

    # Upload the local max vals file to the S3 bucket
    s3.upload_file(tmp_netcdf, output_file_bucket, output_file)
    os.remove(tmp_netcdf)