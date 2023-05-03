import os
import time
import boto3
import pandas as pd
import geopandas as gpd
import numpy as np
import rasterio
from concurrent.futures import ThreadPoolExecutor
from botocore.exceptions import ClientError

# from multiprocessing import Pool

s3 = boto3.client('s3')

class s3_file:
    def __init__(self, bucket, key):
        self.bucket = bucket
        self.key = key
        self.uri = 's3://' + bucket + '/' + key

    ###################################
    @classmethod
    def from_lambda_event(cls, event):
        print("Parsing lambda event to get S3 key and bucket.")
        if "Records" in event:
            message = json.loads(event["Records"][0]['Sns']['Message'])
            data_bucket = message["Records"][0]['s3']['bucket']['name']
            data_key = urllib.parse.unquote_plus(message["Records"][0]['s3']['object']['key'], encoding='utf-8')
        else:
            data_bucket = event['data_bucket']
            data_key = event['data_key']
        return cls(data_bucket, data_key)

    ###################################
    @classmethod
    def from_eventbridge(cls, event):
        configuration = event['resources'][0].split("/")[-1]
        eventbridge_time = datetime.datetime.strptime(event['time'], '%Y-%m-%dT%H:%M:%SZ')

        para = False
        if "_para" in configuration:
            para = True

        if "coastal" in configuration:
            base_config = configuration
            nwm_file_type = 'total_water'
            domain = 'coastal'
            configuration = base_config
        else:
            if "analysis_assim" in configuration:
                base_config = "analysis_assim"
            elif "short_range" in configuration:
                base_config = "short_range"
            elif "medium_range_gfs" in configuration:
                base_config = "medium_range_gfs"
            elif "medium_range_nbm" in configuration:
                base_config = "medium_range_nbm"

            nwm_file_type = configuration.split(base_config)[0][:-1]
            domain = configuration.split(base_config)[-1]
            if domain:
                domain = domain[1:]
                domain = domain.replace("_para", "")
                configuration = f"{base_config}_{domain}"
            else:
                domain = "conus"
                configuration = base_config

        if nwm_file_type == "forcing":
            configuration = f"{nwm_file_type}_{configuration}"

        if "analysis_assim" in base_config:
            if "14day" in configuration:
                reference_time = eventbridge_time.replace(microsecond=0, second=0, minute=0, hour=0)
            elif domain == "coastal":
                reference_time = eventbridge_time.replace(microsecond=0, second=0, minute=0) - datetime.timedelta(hours=1)
            else:
                reference_time = eventbridge_time.replace(microsecond=0, second=0, minute=0)
        elif "short_range" in base_config:
            if domain in ["hawaii", "puertorico"]:
                reference_time = eventbridge_time.replace(microsecond=0, second=0, minute=0) - datetime.timedelta(hours=3)
            elif domain == "alaska":
                reference_time = eventbridge_time.replace(microsecond=0, second=0, minute=0) - datetime.timedelta(hours=1)
            elif domain == "coastal":
                reference_time = eventbridge_time.replace(microsecond=0, second=0, minute=0) - datetime.timedelta(hours=2)
            else:
                reference_time = eventbridge_time.replace(microsecond=0, second=0, minute=0) - datetime.timedelta(hours=1)
        elif "medium_range" in base_config:
            if nwm_file_type == "forcing":
                reference_time = eventbridge_time.replace(microsecond=0, second=0, minute=0) - datetime.timedelta(hours=5)
            elif domain == "alaska":
                reference_time = eventbridge_time.replace(microsecond=0, second=0, minute=0) - datetime.timedelta(hours=6)
            elif domain == "coastal":
                reference_time = eventbridge_time.replace(microsecond=0, second=0, minute=0) - datetime.timedelta(hours=13)
            else:
                reference_time = eventbridge_time.replace(microsecond=0, second=0, minute=0) - datetime.timedelta(hours=7)

        bucket = os.environ.get("DATA_BUCKET_UPLOAD") if os.environ.get("DATA_BUCKET_UPLOAD") else "nomads"

        if "14day" not in configuration:
            reference_time = reference_time - datetime.timedelta(hours=1)
            
        if para and "_para" not in configuration:
            configuration = f"{configuration}_para"
        
        return configuration, reference_time, bucket

    ###################################
    @classmethod
    def get_most_recent_from_configuration(cls, configuration_name, bucket):
        s3 = boto3.client('s3')
        # Set the S3 prefix based on the confiuration
        def get_s3_prefix(configuration_name, date):
            if configuration_name == 'replace_route':
                prefix = f"max_flows/replace_route/{date}/"
            elif configuration_name == 'ahps':
                prefix = f"max_stage/ahps/{date}/"
            else:
                prefix = f"common/data/model/com/nwm/prod/nwm.{date}/{configuration_name}/"
                
            return prefix
            
        # Get all S3 files that match the bucket / prefix
        def list_s3_files(bucket, prefix):
            files = []
            paginator = s3.get_paginator('list_objects_v2')
            for result in paginator.paginate(Bucket=bucket, Prefix=prefix):
                for key in result['Contents']:
                    # Skip folders
                    if not key['Key'].endswith('/'):
                        files.append(key['Key'])
            if len(files) == 0:
                raise Exception("No Files Found.")
            return files
        # Start with looking at files today, but try yesterday if that doesn't work (in case this runs close to midnight)
        today = datetime.datetime.today().strftime('%Y%m%d')
        yesterday = (datetime.datetime.today() - datetime.timedelta(1)).strftime('%Y%m%d')
        try:
            files = list_s3_files(bucket, get_s3_prefix(configuration_name, today))
        except Exception as e:
            print(f"Failed to get files for today ({e}). Trying again with yesterday's files")
            files = list_s3_files(bucket, get_s3_prefix(configuration_name, yesterday))
        # It seems this list is always sorted by default, but adding some sorting logic here may be necessary
        file = cls(bucket=bucket, key=files[-1:].pop())
        return file

    ###################################
    def check_existence(self):
        s3_resource = boto3.resource('s3')
        try:
            s3_resource.Object(self.bucket, self.key).load()
            return True
        except ClientError as e:
            if e.response['Error']['Code'] == "404":
                return False
            else:
                raise

def get_db_credentials(db_type):
    """
    This function pulls database credentials from environment variables.
    It first checks for a password in an environment variable.
    If that doesn't exist, it tries looking or a secret name to query for
    the password using the get_secret_password function.

    Returns:
        db_host (str): The host address of the PostgreSQL database.
        db_name (str): The target database name.
        db_user (str): The database user with write access to authenticate with.
        db_password (str): The password for the db_user.

    """
    db_type = db_type.upper()

    db_host = os.environ[f'{db_type}_DB_HOST']
    db_name = os.environ[f'{db_type}_DB_DATABASE']
    db_user = os.environ[f'{db_type}_DB_USERNAME']
    try:
        db_password = os.getenv(f'{db_type}_DB_PASSWORD')
    except Exception:
        try:
            db_password = get_secret_password(os.getenv(f'{db_type}_RDS_SECRET_NAME'), 'us-east-1', 'password')
        except Exception as e:
            print(f"Couldn't get db password from environment variable or secret name. ({e})")

    return db_host, db_name, db_user, db_password

def get_db_connection(db_type, asynchronous=False):
        import psycopg2
        db_host, db_name, db_user, db_password = get_db_credentials(db_type)
        connection = psycopg2.connect(f"host={db_host} dbname={db_name} user={db_user} password={db_password}", port=5439,async_=asynchronous)
        return connection

def create_inundation_output(huc8, branch, stage_lookup, hand_path, catchment_path):
    """
        Creates the actual inundation output from the stages, catchments, and hand grids
    """
    class HANDDatasetReadError(Exception):
        """ my custom exception class """
    
    try:  
        hand_dataset = rasterio.open(hand_path)  # open HAND grid from S3
        catchment_dataset = rasterio.open(catchment_path)  # open catchment grid from S3  # noqa

        # print("--> Setting up mapping array")
        catchment_nodata = int(catchment_dataset.nodata)  # get no_data value for catchment raster
        valid_catchments = stage_lookup.index.tolist() # parse lookup to get features with >0 stages  # noqa
        hydroids = stage_lookup.index.tolist()  # parse lookup to get all features
        stages = stage_lookup['stage'].tolist()  # parse lookup to get all stages

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
        # print("--> Setting up windows")

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

    # print("Generating polygons")
    from shapely.geometry import shape
    geom = [shape(i['geom']) for i in geoms]
    hydro_ids = [i['hydro_id'] for i in geoms]
    df_final = gpd.GeoDataFrame({'geom':geom, 'hydro_id': hydro_ids}, crs="ESRI:102039", geometry="geom")
    df_final = df_final.dissolve(by="hydro_id")
    df_final['geom'] = df_final['geom'].simplify(5) #Simplifying polygons to ~5m to clean up problematic geometries
    df_final = df_final.to_crs(3857)
    df_final = df_final.set_crs('epsg:3857') 
    df_final = df_final.join(stage_lookup).dropna()  
    df_final = df_final.drop_duplicates()
    
    # print("Adding additional metadata columns")
    df_final = df_final.reset_index()
    df_final = df_final.rename(columns={"index": "hydro_id"})
    df_final['fim_version'] = FIM_PREFIX.split("fim_")[-1]
    df_final['huc8'] = huc8
    df_final['branch'] = branch
    df_final['hand_stage_ft'] = round(df_final['stage'] * 3.28084, 2)
    # df_final['max_rc_stage_ft'] = df_final['max_rc_stage_m'] * 3.28084
    # df_final['max_rc_stage_ft'] = df_final['max_rc_stage_ft'].astype(int)
    df_final['streamflow_cfs'] = round(df_final['discharge_cms'] * 35.315, 2)
    # df_final['max_rc_discharge_cfs'] = round(df_final['max_rc_discharge_cms'] * 35.315, 2)
    # df_final['hydro_id_str'] = df_final['hydro_id'].astype(str)
    # df_final['feature_id_str'] = df_final['feature_id'].astype(str)

    df_final = df_final.drop(columns=["stage", "discharge_cms"])
                
    return df_final

def s3_hydrotables_to_geom_csvs():
    # Create a folder for the local tif outputs
    if not os.path.exists('/tmp/raw_rasters/'):
        os.mkdir('/tmp/raw_rasters/')

    col_names = ['HydroID', 'feature_id', 'NextDownID', 'order_', 'Number of Cells',
        'SurfaceArea (m2)', 'BedArea (m2)', 'TopWidth (m)', 'LENGTHKM',
        'AREASQKM', 'WettedPerimeter (m)', 'HydraulicRadius (m)',
        'WetArea (m2)', 'Volume (m3)', 'SLOPE', 'ManningN', 'stage',
        'default_discharge_cms', 'default_Volume (m3)', 'default_WetArea (m2)',
        'default_HydraulicRadius (m)', 'default_ManningN',
        'precalb_discharge_cms', 'calb_coef_spatial', 'HUC', 'LakeID',
        'subdiv_applied', 'channel_n', 'overbank_n', 'subdiv_discharge_cms',
        'last_updated', 'submitter', 'calb_coef_usgs', 'obs_source',
        'calb_coef_final', 'calb_applied', 'discharge_cms']

    usecols = ['HydroID', 'feature_id', 'stage', 'discharge_cms']

    paginator = s3.get_paginator('list_objects')
    operation_parameters = {'Bucket': BUCKET,
                            'Prefix': FIM_PREFIX+'/',
                            'Delimiter': '/'}
    page_iterator = paginator.paginate(**operation_parameters)
    page_count = 0
    for page in page_iterator:
        page_count += 1
        prefix_objects = page['CommonPrefixes']
        for i, prefix_obj in enumerate(prefix_objects):
            huc_start = time.time()
            print(f"Processing {i+1} of {len(prefix_objects)} on page {page_count}")
            branch_prefix = f'{prefix_obj.get("Prefix")}branches/0/'
            ## UNCOMMENT FOR ALL BRANCHES - NOT JUST 0
            huc_branches_prefix = f'{prefix_obj.get("Prefix")}branches/'
            branches_result = s3.list_objects(Bucket=BUCKET, Prefix=huc_branches_prefix, Delimiter='/')
            branch_prefix_objects = branches_result.get('CommonPrefixes')
            for i, branch_prefix_obj in enumerate(branch_prefix_objects):
                branch_prefix = branch_prefix_obj['Prefix']
            ## END UNCOMMENT
            # [UN]INDENT FROM HERE TO THE END IF [COMMENTED]UNCOMMENTED
                branch_files_result = s3.list_objects(Bucket=BUCKET, Prefix=branch_prefix, Delimiter='/')
                hydro_table_key = None
                for content_obj in branch_files_result.get('Contents'):
                    branch_file_prefix = content_obj['Key']
                    if 'hydroTable' in branch_file_prefix:
                        hydro_table_key = branch_file_prefix
                        geom_file = s3_file(bucket=BUCKET, key=hydro_table_key.replace(FIM_PREFIX, FIM_PREFIX+'_geom'))
                        if geom_file.check_existence():
                            continue
                        
                        start = time.time()
                        hydro_table_key = branch_file_prefix
                        print(f"processing {branch_file_prefix}")
                        # print("...Fetching csvs...")
                        ht = s3.get_object(Bucket=BUCKET, Key=hydro_table_key)['Body']
                        # print("...Reading with pandas...")
                        ht_df = pd.read_csv(ht, header=0, names=col_names, usecols=usecols)
                        # print('...Writing to db...')
                        ht_df['fim_version'] = FIM_VERSION
                        ht_df = ht_df.rename(columns={"HydroID": "hydro_id"})
                        ht_df = ht_df.set_index('hydro_id')
                        huc8 = hydro_table_key.split('/')[1]
                        branch = hydro_table_key.split('/')[3]

                        catchment_path = "/tmp/catchment.tif"
                        hand_path = "/tmp/hand.tif"
                        catchment_key = f'{FIM_PREFIX}/{huc8}/branches/{branch}/gw_catchments_reaches_filtered_addedAttributes_{branch}.tif'
                        hand_key = f'{FIM_PREFIX}/{huc8}/branches/{branch}/rem_zeroed_masked_{branch}.tif'
                        s3.download_file(BUCKET, catchment_key, catchment_path)
                        s3.download_file(BUCKET, hand_key, hand_path)
                        
                        # join metadata to get path to FIM datasets
                        with ThreadPoolExecutor(max_workers=8) as executor:
                            futures = []
                            for stage in stages:
                                ht_df_filtered = ht_df[ht_df['stage']==stage]
                                futures.append(executor.submit(create_inundation_output, huc8=huc8, branch=branch, stage_lookup=ht_df_filtered, hand_path=hand_path, catchment_path=catchment_path))
                            df_branch = pd.DataFrame()
                            for future in futures:
                               df_branch = df_branch.append(future.result())

                        local_csv = f"/tmp/hydrotable_{branch}.csv"
                        df_branch.to_csv(local_csv, index=False)
                        S3_Path = f'{FIM_PREFIX}_geom/{huc8}/branches/{branch}/hydroTable_{branch}.csv'
                        s3.upload_file(local_csv, BUCKET, S3_Path)
                        print(f"Branch Time: {round(time.time()-start,0)} seconds")
            print(f"Total HUC Time: {round(time.time()-huc_start,0)/60} minutes")

def s3_geom_hydrotables_to_db(db_type, schema, table):
    
    # db_engine = get_db_engine("viz")
    conn = get_db_connection(db_type)
    cur = conn.cursor()
    cur.execute(f'TRUNCATE TABLE {schema}.{table};')
    conn.commit()
    start = time.time()
    paginator = s3.get_paginator('list_objects')
    operation_parameters = {'Bucket': BUCKET,
                            'Prefix': FIM_PREFIX+'_geom/',
                            'Delimiter': '/'}
    page_iterator = paginator.paginate(**operation_parameters)
    page_count = 0
    for page in page_iterator:
        page_count += 1
        prefix_objects = page['CommonPrefixes']
        for i, prefix_obj in enumerate(prefix_objects):
            huc_start = time.time()
            print(f"Processing {i+1} of {len(prefix_objects)} on page {page_count}")
            branch_prefix = f'{prefix_obj.get("Prefix")}branches/0/'
            ## UNCOMMENT FOR ALL BRANCHES - NOT JUST 0
            huc_branches_prefix = f'{prefix_obj.get("Prefix")}branches/'
            branches_result = s3.list_objects(Bucket=BUCKET, Prefix=huc_branches_prefix, Delimiter='/')
            branch_prefix_objects = branches_result.get('CommonPrefixes')
            for i, branch_prefix_obj in enumerate(branch_prefix_objects):
                branch_prefix = branch_prefix_obj['Prefix']
            ## END UNCOMMENT
            # [UN]INDENT FROM HERE TO THE END IF [COMMENTED]UNCOMMENTED
                branch_files_result = s3.list_objects(Bucket=BUCKET, Prefix=branch_prefix, Delimiter='/')
                hydro_table_key = None
                for content_obj in branch_files_result.get('Contents'):
                    branch_file_prefix = content_obj['Key']
                    if 'hydroTable' in branch_file_prefix:
                        sql=f"""
                        COPY vizrs.derived.fim_hydrotable (hydro_id,geom,feature_id,fim_version,huc8,branch,hand_stage_ft,streamflow_cfs)
                        FROM 's3://{BUCKET}/{branch_file_prefix}'
                        IAM_ROLE 'arn:aws:iam::526904826677:role/aws-service-role/redshift.amazonaws.com/AWSServiceRoleForRedshift'
                        FORMAT AS CSV DELIMITER ',' IGNOREHEADER 1 QUOTE '"' REGION AS 'us-east-1'
                        """
                        cur.execute(sql)
                        conn.commit()
            print(f"Total HUC Import Time: {round(time.time()-huc_start,0)/60} minutes")
    print(f"Imported {page_count} HUCS in {round(time.time()-start,0)/60} minutes")

########################################################################################################################################
if __name__ == '__main__':
    os.environ['VIZ_DB_HOST'] = "viz-rs-dev.cunnjxnkwkwe.us-east-1.redshift.amazonaws.com"
    os.environ['VIZ_DB_DATABASE'] = "vizrs"
    os.environ['VIZ_DB_USERNAME'] = ""
    os.environ['VIZ_DB_PASSWORD'] = ""

    BUCKET = 'hydrovis-ti-deployment-us-east-1'
    FIM_VERSION = '4_3_3_4'
    FIM_PREFIX = f'fim_{FIM_VERSION}'

    schema = "derived"
    table = "fim_hydrotable"

    stages = [0, 0.3048, 0.6096, 0.9144, 1.2192, 1.524, 1.8288, 2.1336, 2.4384, 2.7432, 3.048, 3.3528, 3.6576, 3.9624, 4.2672, 4.572, 4.8768, 5.1816, 5.4864, 5.7912,
            6.096, 6.4008, 6.7056, 7.0104, 7.3152, 7.62, 7.9248, 8.2296, 8.5344, 8.8392, 9.144, 9.4488, 9.7536, 10.0584, 10.3632, 10.668, 10.9728, 11.2776, 11.5824,
            11.8872, 12.192, 12.4968, 12.8016, 13.1064, 13.4112, 13.716, 14.0208, 14.3256, 14.6304, 14.9352, 15.24, 15.5448, 15.8496, 16.1544, 16.4592, 16.764, 17.0688,
            17.3736, 17.6784, 17.9832, 18.288, 18.5928, 18.8976, 19.2024, 19.5072, 19.812, 20.1168, 20.4216, 20.7264, 21.0312, 21.336, 21.6408, 21.9456, 22.2504,
            22.5552, 22.86, 23.1648, 23.4696, 23.7744, 24.0792, 24.384, 24.6888, 24.9936, 25.2984]

    # s3_hydrotables_to_geom_csvs()
    s3_geom_hydrotables_to_db("viz", schema, table)

    ## Needed to add redshift role access to deployment s3 bucket and kms key
    # Started import at 12:30pm
