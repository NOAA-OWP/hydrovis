import boto3
import rasterio
import numpy as np
import pandas as pd
import geopandas as gpd
import os
import time
import datetime
import re

from viz_classes import s3_file, database

FIM_BUCKET = os.environ['FIM_BUCKET']
FIM_PREFIX = os.environ['FIM_PREFIX']
FIM_VERSION = re.findall("[/_]?(\d*_\d*_\d*_\d*)/?", FIM_PREFIX)[0]

s3 = boto3.client("s3")

class HANDDatasetReadError(Exception):
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
    run_values = event['run_values']
    reference_time = event['reference_time']
    product = event['product']
    fim_config = event['fim_config']
    data_bucket = event['data_bucket']
    data_prefix = event['data_prefix']
    fim_config_name = fim_config['name']
    db_fim_table = fim_config['target_table']
    process_by = fim_config.get('process_by', ['huc'])
    input_variable = fim_config.get('input_variable', 'flow')
    
    reference_date = datetime.datetime.strptime(reference_time, "%Y-%m-%d %H:%M:%S")
    date = reference_date.strftime("%Y%m%d")
    hour = reference_date.strftime("%H")
    huc8_branch = run_values['huc8_branch']
    huc8 = huc8_branch.split("-")[0]
    branch = huc8_branch.split("-")[1]
    s3_path_piece = ''
    
    if "catchments" in db_fim_table:
        df_inundation = create_inundation_catchment_boundary(huc8, branch)
    else:
        print(f"Processing FIM for huc {huc8} and branch {branch}")

        s3_path_piece = '/'.join([run_values[by] for by in process_by])
        subsetted_data = f"{data_prefix}/{product}/{fim_config_name}/workspace/{date}/{hour}/data/{s3_path_piece}_data.csv"

        print(f"Processing HUC {huc8} for {fim_config_name} for {date}T{hour}:00:00Z")

        if input_variable == 'stage':
            stage_lookup = s3_csv_to_df(data_bucket, subsetted_data)
            stage_lookup = stage_lookup.set_index('hydro_id')
        else:
            # Validate main stem datasets by checking cathment, hand, and rating curves existence for the HUC
            catchment_key = f'{FIM_PREFIX}/{huc8}/branches/{branch}/gw_catchments_reaches_filtered_addedAttributes_{branch}.tif'
            catch_exists = s3_file(FIM_BUCKET, catchment_key).check_existence()

            hand_key = f'{FIM_PREFIX}/{huc8}/branches/{branch}/rem_zeroed_masked_{branch}.tif'
            hand_exists = s3_file(FIM_BUCKET, hand_key).check_existence()

            rating_curve_key = f'{FIM_PREFIX}/{huc8}/branches/{branch}/hydroTable_{branch}.csv'
            rating_curve_exists = s3_file(FIM_BUCKET, rating_curve_key).check_existence()

            stage_lookup = pd.DataFrame()
            if catch_exists and hand_exists and rating_curve_exists:
                print("->Calculating flood depth")
                stage_lookup = calculate_stage_values(rating_curve_key, data_bucket, subsetted_data, huc8_branch)  # get stages
            else:
                print(f"catchment, hand, or rating curve are missing for huc {huc8} and branch {branch}:\nCatchment exists: {catch_exists} ({catchment_key})\nHand exists: {hand_exists} ({hand_key})\nRating curve exists: {rating_curve_exists} ({rating_curve_key})")

        # If no features with above zero stages are present, then just copy an unflood raster instead of processing nothing
        if stage_lookup.empty:
            print("No reaches with valid stages")
            return

        # Run the desired configuration
        df_inundation = create_inundation_output(huc8, branch, stage_lookup, reference_time, input_variable)

    print(f"Adding data to {db_fim_table}")# Only process inundation configuration if available data
    db_schema = db_fim_table.split(".")[0]
    db_table = db_fim_table.split(".")[-1]

    try:
        if any(x in db_schema for x in ["aep", "fim_catchments", "catfim"]):
            process_db = database(db_type="egis")
        else:
            process_db = database(db_type="viz")

        df_inundation.to_postgis(db_table, con=process_db.engine, schema=db_schema, if_exists='append')
    except Exception as e:
        process_db.engine.dispose()
        raise Exception(f"Failed to add inundation data to DB for {huc8}-{branch} - ({e})")
    
    process_db.engine.dispose()
    
    print(f"Successfully processed tif for HUC {huc8} and branch {branch} for {product} for {reference_time}")

    return

def create_inundation_catchment_boundary(huc8, branch):
    """
        Creates the catchment boundary polygons
    """
    catchment_key = f'{FIM_PREFIX}/{huc8}/branches/{branch}/gw_catchments_reaches_filtered_addedAttributes_{branch}.tif'
    
    catchment_dataset = None
    try:
        print("--> Connecting to S3 datasets")
        tries = 0
        raster_open_success = False
        while tries < 3:
            try:
                catchment_dataset = rasterio.open(f's3://{FIM_BUCKET}/{catchment_key}')  # open catchment grid from S3  # noqa
                tries = 3
                raster_open_success = True
            except Exception as e:
                tries += 1
                time.sleep(30)
                print(f"Failed to open datasets. Trying again in 30 seconds - ({e})")

        if not raster_open_success:
            raise HANDDatasetReadError("Failed to open HAND and Catchment datasets")
            
        print("--> Setting up mapping array")
        profile = catchment_dataset.profile  # get the rasterio profile so the output can use the profile and match the input  # noqa

        # set the output nodata to 0
        profile['nodata'] = 0
        profile['dtype'] = "int32"

        # Open the output raster using rasterio. This will allow the inner function to be parallel and write to it
        print("--> Setting up windows")

        # Get the list of windows according to the raster metadata so they can be looped through
        windows = [window for ij, window in catchment_dataset.block_windows()]

        # This function will be run for each raster window.
        def process(window):
            """
                This function is run for each raster window in parallel. The function will read in the appropriate
                window of the HAND and catchment datasets for main stem and/or full resolution. The stages will
                then be mapped from a numpy array to the catchment window. This will create a windowed stage array.
                The stage array is then compared to the HAND window array to create an inundation array where the
                HAND values are gte to the stage values.

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
                raise HANDDatasetReadError("Failed to open Catchment dataset window")
            
            from rasterio.features import shapes
            mask = None
            results = (
            {'hydro_id': int(v), 'geom': s}
            for i, (s, v) 
            in enumerate(
                shapes(catchment_window, mask=mask, transform=rasterio.windows.transform(window, catchment_dataset.transform))) if int(v))

            return list(results)

        # Use threading to parallelize the processing of the inundation windows
        geoms = []
        for window in windows:
            catchment_windows = process(window)
            if catchment_windows:
                geoms.extend(catchment_windows)
                        
    except Exception as e:
        raise e
    finally:
        if catchment_dataset is not None:
            catchment_dataset.close()

    print("Generating polygons")
    from shapely.geometry import shape
    geom = [shape(i['geom']) for i in geoms]
    hydro_ids = [i['hydro_id'] for i in geoms]
    df_final = gpd.GeoDataFrame({'geom':geom, 'hydro_id': hydro_ids}, crs="ESRI:102039", geometry="geom")
    df_final = df_final.dissolve(by="hydro_id")
    df_final = df_final.to_crs(3857)
    df_final = df_final.set_crs('epsg:3857')
    
    if df_final.index.has_duplicates:
        print("dropping duplicates")
        df_final = df_final.drop_duplicates()
    
    print("Adding additional metadata columns")
    df_final = df_final.reset_index()
    df_final = df_final.rename(columns={"index": "hydro_id"})
    df_final['fim_version'] = FIM_VERSION
    df_final['huc8'] = huc8
    df_final['branch'] = branch
                
    return df_final
    

def create_inundation_output(huc8, branch, stage_lookup, reference_time, input_variable):
    """
        Creates the actual inundation output from the stages, catchments, and hand grids
    """
    # join metadata to get path to FIM datasets
    catchment_key = f'{FIM_PREFIX}/{huc8}/branches/{branch}/gw_catchments_reaches_filtered_addedAttributes_{branch}.tif'
    hand_key = f'{FIM_PREFIX}/{huc8}/branches/{branch}/rem_zeroed_masked_{branch}.tif'
    
    try:
        print(f"Creating inundation for huc {huc8} and branch {branch}")
        
        # Create a folder for the local tif outputs
        if not os.path.exists('/tmp/raw_rasters/'):
            os.mkdir('/tmp/raw_rasters/')
        
        print("--> Connecting to S3 datasets")
        tries = 0
        raster_open_success = False
        while tries < 3:
            try:
                hand_dataset = rasterio.open(f's3://{FIM_BUCKET}/{hand_key}')  # open HAND grid from S3
                catchment_dataset = rasterio.open(f's3://{FIM_BUCKET}/{catchment_key}')  # open catchment grid from S3  # noqa
                tries = 3
                raster_open_success = True
            except Exception as e:
                tries += 1
                time.sleep(30)
                print(f"Failed to open datasets. Trying again in 30 seconds - ({e})")

        if not raster_open_success:
            raise HANDDatasetReadError("Failed to open HAND and Catchment datasets")
            
        print("--> Setting up mapping array")
        catchment_nodata = int(catchment_dataset.nodata)  # get no_data value for catchment raster
        valid_catchments = stage_lookup.index.tolist() # parse lookup to get features with >0 stages  # noqa
        hydroids = stage_lookup.index.tolist()  # parse lookup to get all features
        stages = stage_lookup['hand_stage_m'].tolist()  # parse lookup to get all stages

        k = np.array(hydroids)  # Create a feature numpy array from the list
        v = np.array(stages)  # Create a stage numpy array from the list

        hydro_id_max = k.max()  # Get the max feature id in the array

        hand_nodata = hand_dataset.nodata  # get the no_data value for the HAND raster
        hand_dtype = hand_dataset.dtypes[0]  # get the dtype for the HAND raster
        profile = hand_dataset.profile  # get the rasterio profile so the output can use the profile and match the input  # noqa

        # set the output nodata to 0
        profile['nodata'] = 0
        profile['dtype'] = "int32"

        # Open the output raster using rasterio. This will allow the inner function to be parallel and write to it
        print("--> Setting up windows")

        # Get the list of windows according to the raster metadata so they can be looped through
        windows = [window for ij, window in hand_dataset.block_windows()]

        # This function will be run for each raster window.
        def process(window):
            """
                This function is run for each raster window in parallel. The function will read in the appropriate
                window of the HAND and catchment datasets for main stem and/or full resolution. The stages will
                then be mapped from a numpy array to the catchment window. This will create a windowed stage array.
                The stage array is then compared to the HAND window array to create an inundation array where the
                HAND values are gte to the stage values.

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
                raise HANDDatasetReadError("Failed to open Catchment dataset window")

            unique_window_catchments = np.unique(catchment_window).tolist()  # Get a list of unique hydroids within the window  # noqa
            window_valid_catchments = [catchment for catchment in unique_window_catchments if catchment in valid_catchments]  # Check to see if any hydroids with stages >0 are inside this window  # noqa
            # Only process if there are hydroids with stage >0 in this window
            if not window_valid_catchments:
                return 


            tries = 0
            hand_open_success = False
            while tries < 3:
                try:
                    hand_window = hand_dataset.read(window=window)
                    tries = 3
                    hand_open_success = True
                except Exception as e:
                    tries += 1
                    time.sleep(10)
                    print(f"Failed to open catchment. Trying again in 10 seconds - ({e})")

            if not hand_open_success:
                raise HANDDatasetReadError("Failed to open HAND dataset window")
            
            # Create an empty numpy array with the nodata value that will be overwritten
            inundation_window = np.full(catchment_window.shape, hand_nodata, hand_dtype)

            # If catchment window values exist, then find the max between the stage mapper and the window
            mapping_ar_max = max(hydro_id_max, catchment_window.max())

            # Create a stage mapper that will convert hydroids to their corresponding stage. -9999 is null or
            # no value. we cant use 0 because it will mess up the mapping and use the 0 index
            mapping_ar = np.full(mapping_ar_max+1, -9999, dtype="float32")
            mapping_ar[k] = v

            catchment_window[np.where(catchment_window == catchment_nodata)] = 0  # Convert catchment values to 0 where the catchment = catchment_nodata  # noqa
            catchment_window[np.where(hand_window == hand_nodata)] = 0  # Convert catchment values to 0 where the HAND = HAND_nodata. THis will ensure we are only processing where we have HAND values!  # noqa

            reclass_window = mapping_ar[catchment_window]  # Convert the catchment to stage

            condition1 = reclass_window > hand_window  # Select where stage is gte to HAND
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
                {'hydro_id': int(v), 'geom': s}
                for i, (s, v) 
                in enumerate(
                    shapes(inundation_window, mask=mask, transform=rasterio.windows.transform(window, hand_dataset.transform))) if int(v))
                    
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
        if hand_dataset is not None:
            hand_dataset.close()

        if catchment_dataset is not None:
            catchment_dataset.close()

    print("Generating polygons")
    from shapely.geometry import shape
    geom = [shape(i['geom']) for i in geoms]
    hydro_ids = [i['hydro_id'] for i in geoms]
    df_final = gpd.GeoDataFrame({'geom':geom, 'hydro_id': hydro_ids}, crs="ESRI:102039", geometry="geom")
    df_final = df_final.dissolve(by="hydro_id")
    df_final['geom'] = df_final['geom'].simplify(5) #Simplifying polygons to ~5m to clean up problematic geometries
    df_final = df_final.to_crs(3857)
    df_final = df_final.set_crs('epsg:3857')
        
    df_final = df_final.join(stage_lookup).dropna()
    
    if df_final.index.has_duplicates:
        print("dropping duplicates")
        df_final = df_final.drop_duplicates()
    
    print("Adding additional metadata columns")
    df_final = df_final.reset_index()
    df_final = df_final.rename(columns={"index": "hydro_id"})
    df_final['fim_version'] = FIM_VERSION
    df_final['reference_time'] = reference_time
    df_final['huc8'] = huc8
    df_final['branch'] = branch
    df_final['fim_stage_ft'] = round(df_final['hand_stage_m'] * 3.28084, 2)
    df_final['hydro_id_str'] = df_final['hydro_id'].astype(str)
    df_final['feature_id_str'] = df_final['feature_id'].astype(str)
    
    if input_variable == 'stage':
        drop_columns = ['hand_stage_m', 'huc8_branch', 'huc']
    else:
        df_final['max_rc_stage_ft'] = df_final['max_rc_stage_m'] * 3.28084
        df_final['max_rc_stage_ft'] = df_final['max_rc_stage_ft'].astype(int)
        df_final['streamflow_cfs'] = round(df_final['streamflow_cms'] * 35.315, 2)
        df_final['max_rc_discharge_cfs'] = round(df_final['max_rc_discharge_cms'] * 35.315, 2)
        drop_columns = ["hand_stage_m", "max_rc_stage_m", "streamflow_cms", "max_rc_discharge_cms"]

    df_final = df_final.drop(columns=drop_columns)
                
    return df_final

def s3_csv_to_df(bucket, key):
    basename = os.path.basename(key)
    local_file = f"/tmp/{basename}"

    print(f"Downloading {key} from {bucket}")
    s3.download_file(bucket, key, local_file)
    df = pd.read_csv(local_file)
    os.remove(local_file)
    
    return df

def calculate_stage_values(hydrotable_key, subsetted_streams_bucket, subsetted_streams, huc8_branch):
    """
        Converts streamflow values to stage using the rating curve and linear interpolation because rating curve intervals
        
        Arguments:
            local_hydrotable (str): Path to local copy of the branch hydrotable
            df_nwm (DataFrame): A pandas dataframe with columns for feature id and desired streamflow column
            
        Returns:
            stage_dict (dict): A dictionary with the hydroid as the key and interpolated stage as the value
    """
    df_hydro = s3_csv_to_df(FIM_BUCKET, hydrotable_key)
    df_hydro = df_hydro[['HydroID', 'feature_id', 'stage', 'discharge_cms', 'LakeID']]
    
    df_hydro_max = df_hydro.sort_values('stage').groupby('HydroID').tail(1)
    df_hydro_max = df_hydro_max.set_index('HydroID')
    df_hydro_max = df_hydro_max[['stage', 'discharge_cms']].rename(columns={'stage': 'max_rc_stage_m', 'discharge_cms': 'max_rc_discharge_cms'})

    df_forecast = s3_csv_to_df(subsetted_streams_bucket, subsetted_streams)
    df_forecast = df_forecast.loc[df_forecast['huc8_branch']==huc8_branch]
    df_forecast['hand_stage_m'] = df_forecast.apply(lambda row : interpolate_stage(row, df_hydro), axis=1)
    
    print(f"Removing {len(df_forecast[df_forecast['hand_stage_m'].isna()])} reaches with a NaN interpolated stage")
    df_forecast = df_forecast[~df_forecast['hand_stage_m'].isna()]

    print(f"Removing {len(df_forecast[df_forecast['hand_stage_m']==0])} reaches with a 0 interpolated stage")
    df_forecast = df_forecast[df_forecast['hand_stage_m']!=0]

    df_forecast = df_forecast.drop(columns=['huc8_branch', 'huc'])
    df_forecast = df_forecast.set_index('hydro_id')
    df_forecast = df_forecast.join(df_hydro_max)
    print(f"{len(df_forecast)} reaches will be processed")
     
    return df_forecast

def interpolate_stage(df_row, df_hydro):
    hydro_id = df_row['hydro_id']
    forecast = df_row['streamflow_cms']
    
    if hydro_id not in df_hydro['HydroID'].values:
        return np.nan
    
    subet_hydro = df_hydro.loc[df_hydro['HydroID']==hydro_id, ['discharge_cms', 'stage']]
    discharge = subet_hydro['discharge_cms'].values
    stage = subet_hydro['stage'].values
    
    interpolated_stage = round(np.interp(forecast, discharge, stage), 2)
    
    return interpolated_stage
