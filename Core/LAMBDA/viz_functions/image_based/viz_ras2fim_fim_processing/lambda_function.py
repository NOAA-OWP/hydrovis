import json
import re
import boto3
import rasterio
import numpy as np
import pandas as pd
import geopandas as gpd
import os
import time
import datetime
from shapely.geometry import shape
from shapely.ops import unary_union

from viz_classes import s3_file, database

FIM_BUCKET = os.environ['FIM_BUCKET']
RAS2FIM_PREFIX = os.environ['RAS2FIM_PREFIX']
FIM_VERSION = re.findall("[/_]?(\d*_\d*_\d*)/?", RAS2FIM_PREFIX)[0]

s3 = boto3.client("s3")

class DatasetReadError(Exception):
    """ my custom exception class """

def lambda_handler(event, context):
    """
        The lambda handler is the function that is kicked off with the lambda. This function will coordinate
        the overall workflow from retrieving data, parsing it, kicking off the inundation workflow, saving the outputs,
        and then kicking off the next lambda which optimizes the raster for the cloud

        Args:
            event(event object): An event is a JSON-formatted document that contains data for a Lambda function to
                                 process
            context(object): Provides methods and properties that provide information about the invocation, function,
                             and runtime environment
    """
    # Parse the event argument to get the necessary arguments for the function
    db_fim_table = event['db_fim_table']
    reference_time = event['reference_time']
    service = event['service']
    fim_config = event['fim_config']
    data_bucket = event['data_bucket']
    data_prefix = event['data_prefix']
    huc8 = event['huc8']
    
    reference_date = datetime.datetime.strptime(reference_time, "%Y-%m-%d %H:%M:%S")
    date = reference_date.strftime("%Y%m%d")
    hour = reference_date.strftime("%H")
    
    catchment_key = f'{RAS2FIM_PREFIX}/{huc8}/feature_id.tif'
    catch_exists = s3_file(FIM_BUCKET, catchment_key).check_existence()
    
    print(f"Processing RAS2REM for huc {huc8}")

    subsetted_streams = f"{data_prefix}/{huc8}.csv"

    print(f"Processing HUC {huc8} for {fim_config} for {date}T{hour}:00:00Z")
    ras2rem_key = f'{RAS2FIM_PREFIX}/{huc8}/rem_12090301_meter_blocked.tif'
    ras2rem_exists = s3_file(FIM_BUCKET, ras2rem_key).check_existence()

    rating_curve_key = f'{RAS2FIM_PREFIX}/{huc8}/rating_curve.csv'
    rating_curve_exists = s3_file(FIM_BUCKET, rating_curve_key).check_existence()

    stage_lookup = pd.DataFrame()
    if catch_exists and ras2rem_exists and rating_curve_exists:
        print("->Calculating flood depth")
        stage_lookup = calculate_stage_values(rating_curve_key, data_bucket, subsetted_streams)  # get stages
    else:
        print(f"catchment, ras2rem, or rating curve are missing for huc {huc8}")

    # If no features with above zero stages are present, then just copy an unflood raster instead of processing nothing
    if stage_lookup.empty:
        print("No reaches with valid stages")
        return

    # Run the desired configuration
    df_inundation = create_inundation_output(huc8, stage_lookup, reference_time, catchment_key, ras2rem_key)

    print(f"Adding data to {db_fim_table}")# Only process inundation configuration if available data
    db_schema = db_fim_table.split(".")[0]
    db_table = db_fim_table.split(".")[-1]

    try:
        if "reference" in db_schema or "fim_catchments" in db_schema:
            process_db = database(db_type="egis")
        else:
            process_db = database(db_type="viz")

        df_inundation.to_postgis(db_table, con=process_db.engine, schema=db_schema, if_exists='append')
    except Exception as e:
        process_db.engine.dispose()
        raise Exception(f"Failed to add inundation data to DB for {huc8}-{branch} - ({e})")
    
    process_db.engine.dispose()
    
    print(f"Successfully processed tif for HUC {huc8} and branch {branch} for {service} for {reference_time}")

    return df_inundation

def create_inundation_output(huc8, stage_lookup, reference_time, catchment_key, ras2rem_key):
    """
        Creates the actual inundation output from the stages, catchments, and ras2rem grids
    """
    try:
        print(f"Creating inundation for huc {huc8}")
        
        # Create a folder for the local tif outputs
        if not os.path.exists('/tmp/raw_rasters/'):
            os.mkdir('/tmp/raw_rasters/')
        
        print("--> Connecting to S3 datasets")
        tries = 0
        raster_open_success = False
        while tries < 3:
            try:
                ras2rem_dataset = rasterio.open(f's3://{FIM_BUCKET}/{ras2rem_key}')  # open ras2rem grid from S3
                catchment_dataset = rasterio.open(f's3://{FIM_BUCKET}/{catchment_key}')  # open catchment grid from S3  # noqa
                tries = 3
                raster_open_success = True
            except Exception as e:
                tries += 1
                time.sleep(30)
                print(f"Failed to open datasets. Trying again in 30 seconds - ({e})")

        if not raster_open_success:
            raise DatasetReadError("Failed to open ras2rem and Catchment datasets")
            
        print("--> Setting up mapping array")
        catchment_nodata = int(catchment_dataset.nodata) if not np.isnan(catchment_dataset.nodata) else -9999 # get no_data value for catchment raster
        valid_catchments = stage_lookup.index.tolist() # parse lookup to get features with >0 stages  # noqa
        hydroids = stage_lookup.index.tolist()  # parse lookup to get all features
        stages = stage_lookup['ras2rem_stage_m'].tolist()  # parse lookup to get all stages

        k = np.array(hydroids)  # Create a feature numpy array from the list
        v = np.array(stages)  # Create a stage numpy array from the list

        hydro_id_max = k.max()  # Get the max feature id in the array

        ras2rem_nodata = ras2rem_dataset.nodata  # get the no_data value for the ras2rem raster
        ras2rem_dtype = ras2rem_dataset.dtypes[0]  # get the dtype for the ras2rem raster
        profile = ras2rem_dataset.profile  # get the rasterio profile so the output can use the profile and match the input  # noqa

        # set the output nodata to 0
        profile['nodata'] = 0
        profile['dtype'] = "int32"

        # Open the output raster using rasterio. This will allow the inner function to be parallel and write to it
        print("--> Setting up windows")

        # Get the list of windows according to the raster metadata so they can be looped through
        windows = [window for ij, window in ras2rem_dataset.block_windows()]

        # This function will be run for each raster window.
        def process(window):
            """
                This function is run for each raster window in parallel. The function will read in the appropriate
                window of the ras2rem and catchment datasets for main stem and/or full resolution. The stages will
                then be mapped from a numpy array to the catchment window. This will create a windowed stage array.
                The stage array is then compared to the ras2rem window array to create an inundation array where the
                ras2rem values are gte to the stage values.

                Each windowed inundation array is then saved to the output array for that specific window that was
                ran.

                For more information on rasterio window processing, see
                https://rasterio.readthedocs.io/en/latest/topics/windowed-rw.html

                If main stem AND full resolution are ran, then the inundation arrays for each configuration will be
                compared and the highest value for each element in the array will be used. This is how we 'merge'
                the two configurations. Because the extents of fr and ms are not the same, we do have to reshape
                the arrays a bit to allow for the comparison
            """
            tries = 0
            catchment_open_success = False
            while tries < 3:
                try:
                    catchment_window = catchment_dataset.read(window=window)  # Read the dataset for the specified window  # noqa
                    tries = 3
                    catchment_open_success = True
                except Exception as e:
                    tries += 1
                    time.sleep(10)
                    print(f"Failed to open catchment. Trying again in 10 seconds - ({e})")

            if not catchment_open_success:
                raise DatasetReadError("Failed to open Catchment dataset window")

            unique_window_catchments = np.unique(catchment_window).tolist()  # Get a list of unique hydroids within the window  # noqa
            window_valid_catchments = [catchment for catchment in unique_window_catchments if catchment in valid_catchments]  # Check to see if any hydroids with stages >0 are inside this window  # noqa
            # Only process if there are hydroids with stage >0 in this window
            if not window_valid_catchments:
                return 


            tries = 0
            ras2rem_open_success = False
            while tries < 3:
                try:
                    ras2rem_window = ras2rem_dataset.read(window=window)
                    tries = 3
                    ras2rem_open_success = True
                except Exception as e:
                    tries += 1
                    time.sleep(10)
                    print(f"Failed to open catchment. Trying again in 10 seconds - ({e})")

            if not ras2rem_open_success:
                raise DatasetReadError("Failed to open ras2rem dataset window")
            
            # Create an empty numpy array with the nodata value that will be overwritten
            inundation_window = np.full(catchment_window.shape, ras2rem_nodata, ras2rem_dtype)

            # If catchment window values exist, then find the max between the stage mapper and the window
            mapping_ar_max = max(hydro_id_max, catchment_window.max())

            # Create a stage mapper that will convert hydroids to their corresponding stage. -9999 is null or
            # no value. we cant use 0 because it will mess up the mapping and use the 0 index
            mapping_ar = np.full(mapping_ar_max+1, -9999, dtype="float32")
            mapping_ar[k] = v
            
            catchment_window[np.where(catchment_window == catchment_nodata)] = 0  # Convert catchment values to 0 where the catchment = catchment_nodata  # noqa
            catchment_window[np.where(ras2rem_window == ras2rem_nodata)] = 0  # Convert catchment values to 0 where the ras2rem = ras2rem_nodata. THis will ensure we are only processing where we have ras2rem values!  # noqa
            
            reclass_window = mapping_ar[catchment_window]  # Convert the catchment to stage

            condition1 = reclass_window > ras2rem_window  # Select where stage is gte to ras2rem
            condition2 = reclass_window != -9999  # Select where stage is valid
            conditions = (condition1) & (condition2)

            inundation_window = np.where(conditions, catchment_window, 0).astype('int32')

            # Checking to see if there is any inundated areas in the window
            if not inundation_window[np.where(inundation_window != 0)].any():
                return 

            if np.max(inundation_window) != 0:
                from rasterio.features import shapes
                mask = None
                results = (
                {'feature_id': int(v), 'geom': s}
                for i, (s, v) 
                in enumerate(
                    shapes(inundation_window, mask=mask, transform=rasterio.windows.transform(window, ras2rem_dataset.transform))) if int(v))
                    
                return list(results)

        # Use threading to parallelize the processing of the inundation windows
        geoms = []
        for window in windows:
            inundation_windows = process(window)
            if inundation_windows:
                geoms.extend(inundation_windows)
                        
    except Exception as e:
        raise e
    finally:
        if ras2rem_dataset is not None:
            ras2rem_dataset.close()

        if catchment_dataset is not None:
            catchment_dataset.close()

    print("Generating polygons")
    from shapely.geometry import shape
    geom = [shape(i['geom']) for i in geoms]
    feature_ids = [i['feature_id'] for i in geoms]
    df_final = gpd.GeoDataFrame({'geom':geom, 'feature_id': feature_ids}, crs="epsg:3857", geometry="geom")
    df_final = df_final.dissolve(by="feature_id")
        
    df_final = df_final.join(stage_lookup).dropna()
    
    df_final = df_final.drop_duplicates()
    
    print("Adding additional metadata columns")
    df_final = df_final.reset_index()
    df_final = df_final.rename(columns={"index": "feature_id"})
    df_final['fim_version'] = FIM_VERSION
    df_final['reference_time'] = reference_time
    df_final['huc8'] = huc8
    df_final['fim_stage_ft'] = round(df_final['ras2rem_stage_m'] * 3.28084, 2)
    df_final['max_rc_stage_ft'] = df_final['max_rc_stage_m'] * 3.28084
    df_final['max_rc_stage_ft'] = df_final['max_rc_stage_ft'].astype(int)
    df_final['streamflow_cfs'] = round(df_final['streamflow_cms'] * 35.315, 2)
    df_final['max_rc_discharge_cfs'] = round(df_final['max_rc_discharge_cms'] * 35.315, 2)
    df_final['nwm_feature_id_str'] = df_final['feature_id'].astype(str)
    df_final['fim_model_hydro_id'] = df_final['feature_id']
    df_final['fim_model_hydro_id_str'] = df_final['fim_model_hydro_id'].astype(str)

    df_final = df_final.rename(columns={"feature_id": "nwm_feature_id"})
    df_final = df_final.drop(columns=["ras2rem_stage_m", "max_rc_stage_m", "streamflow_cms", "max_rc_discharge_cms"])
                
    return df_final

def calculate_stage_values(hydrotable_key, subsetted_streams_bucket, subsetted_streams):
    """
        Converts streamflow values to stage using the rating curve and linear interpolation because rating curve intervals
        
        Arguments:
            local_hydrotable (str): Path to local copy of the branch hydrotable
            df_nwm (DataFrame): A pandas dataframe with columns for feature id and desired streamflow column
            
        Returns:
            stage_dict (dict): A dictionary with the hydroid as the key and interpolated stage as the value
    """
    local_hydrotable = "/tmp/hydrotable.csv"
    local_data = "/tmp/data.csv"
    
    print("Downloading hydrotable")
    s3.download_file(FIM_BUCKET, hydrotable_key, local_hydrotable)

    print("Downloading streamflow data")
    s3.download_file(subsetted_streams_bucket, subsetted_streams, local_data)
    
    df_hydro = pd.read_csv(local_hydrotable)
    df_hydro = df_hydro[['feature_id', 'stage_m', 'discharge_cms']]
    os.remove(local_hydrotable)
    
    df_hydro_max = df_hydro.sort_values('stage_m').groupby('feature_id').tail(1)
    df_hydro_max = df_hydro_max.set_index('feature_id')
    df_hydro_max = df_hydro_max[['stage_m', 'discharge_cms']].rename(columns={'stage_m': 'max_rc_stage_m', 'discharge_cms': 'max_rc_discharge_cms'})

    df_forecast = pd.read_csv(local_data)
    os.remove(local_data)
    df_forecast['ras2rem_stage_m'] = df_forecast.apply(lambda row : interpolate_stage(row, df_hydro), axis=1)
    
    print(f"Removing {len(df_forecast[df_forecast['ras2rem_stage_m'].isna()])} reaches with a NaN interpolated stage")
    df_forecast = df_forecast[~df_forecast['ras2rem_stage_m'].isna()]

    print(f"Removing {len(df_forecast[df_forecast['ras2rem_stage_m']==0])} reaches with a 0 interpolated stage")
    df_forecast = df_forecast[df_forecast['ras2rem_stage_m']!=0]

    df_forecast = df_forecast[['ras2rem_stage_m', 'streamflow_cms', 'feature_id']].set_index('feature_id')
    df_forecast = df_forecast.join(df_hydro_max)
    print(f"{len(df_forecast)} reaches will be processed")
     
    return df_forecast

def interpolate_stage(df_row, df_hydro):
    feature_id = df_row['feature_id']
    forecast = df_row['streamflow_cms']
    
    if feature_id not in df_hydro['feature_id'].values:
        return np.nan
    
    subet_hydro = df_hydro.loc[df_hydro['feature_id']==feature_id, ['discharge_cms', 'stage_m']]
    discharge = subet_hydro['discharge_cms'].values
    stage = subet_hydro['stage_m'].values
    
    interpolated_stage = round(np.interp(forecast, discharge, stage), 2)
    
    return interpolated_stage
