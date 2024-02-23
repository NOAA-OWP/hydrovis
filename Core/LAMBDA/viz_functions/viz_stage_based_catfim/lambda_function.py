import datetime as dt
import json
import os
import threading
import time

import boto3
import botocore
import geopandas as gpd
import numpy as np
import pandas as pd
import requests

from viz_classes import database

INITIALIZE_PIPELINE_FUNCTION = os.environ['INITIALIZE_PIPELINE_FUNCTION']
NUM_THREADS = 15
SEA_LEVEL_SITES = ['QUTG1', 'AUGG1', 'BAXG1', 'LAMF1', 'ADLG1', 'HRAG1', 'STNG1']
CATEGORIES = ['action', 'minor', 'moderate', 'major', 'record']

def lambda_handler(event, context):
    """
        The lambda handler is the function that is kicked off with the lambda. This function will take a forecast file,
        extract features with streamflows above 1.5 year threshold, and then kick off lambdas for each HUC with valid
        data.

        Args:
            event(event object): An event is a JSON-formatted document that contains data for a Lambda function to
                                 process
            context(object): Provides methods and properties that provide information about the invocation, function,
                             and runtime environment
    """
    viz_db = database(db_type="viz")
    print("Getting raw stage data from database...")
    # Creates ingest.stage_based_catfim_sites
    viz_db.run_sql_file_in_db('ingest.sql')  
    # Queries from ingest.stage_based_catfim_sites (created abvove)
    df = viz_db.run_sql_in_db('SELECT * FROM ingest.stage_based_catfim_sites')
    df['datum_adj_ft'] = None
    session = requests.Session()
    mapped_sites_df = df[df['mapped'] == True]
    unique_rows = mapped_sites_df.drop_duplicates(['nws_station_id', 'usgs_datum'])
    num_rows = unique_rows['nws_station_id'].count()
    rows_split = np.array_split(unique_rows, NUM_THREADS)
    threads = []
    print(f"Processing {num_rows} rows across {NUM_THREADS} threads...")
    progress = {'counter': 0, 'total': num_rows, 'logged': []}
    for rows_group in rows_split:
        thread = threading.Thread(target=process_group, args=(df, rows_group, session, progress))
        threads.append(thread)
        thread.start()
        time.sleep(1)

    for thread in threads:
        thread.join()
    
    for sea_level_site in SEA_LEVEL_SITES:
        df.loc[df['nws_station_id'] == sea_level_site, 'status'] += 'thresholds seem to be based on sea level and not channel thalweg;'
        df.loc[df['nws_station_id'] == sea_level_site, 'mapped'] = False

    # Add adjusted stage values
    # Update status if any negative
    # Set mapped to false if all negative

    for cat in CATEGORIES:
        df[f'adj_{cat}_stage_m'] = np.nan
        df[f'adj_{cat}_stage_ft'] = np.nan

    for i, row in df.iterrows():
        cat_vals = []
        for cat in CATEGORIES:
            adj_cat_stage_m = np.nan
            try:
                adj_cat_stage_m = ((row[f'{cat}_stage'] + row.datum_adj_ft + row.usgs_datum) * 0.3048) - row.dem_adj_elevation
                df.at[i, f'adj_{cat}_stage_m'] = adj_cat_stage_m
                df.at[i, f'adj_{cat}_stage_ft'] = adj_cat_stage_m * 3.28084
                if adj_cat_stage_m < 0:
                    df.at[i, 'status'] += f'datum-adjusted {cat} threshold less than 0; '
            except TypeError:
                pass
            finally:
                cat_vals.append(adj_cat_stage_m)

        if all(np.isnan(x) or x < 0 for x in cat_vals):
            df.at[i, 'mapped'] = False

    print("Writing results back to database...")
    df.to_sql(con=viz_db.engine, schema='ingest', name='stage_based_catfim_sites', index=False, if_exists='replace')
    print("Triggering initialize_pipeline...")
    trigger_initialize_pipeline()
    print("ALL DONE!")

def process_group(full_df, subset_df, session=None, progress=None):
    for _, row in subset_df.iterrows():
        data = {}
        lid = row['nws_station_id'].lower()
        # Always default to using USGS data first, if available
        if all(row[x] is not None for x in ['usgs_datum', 'usgs_vcs', 'usgs_lat', 'usgs_lon', 'usgs_crs']):
            data['datum'] = row['usgs_datum']
            data['vcs'] = row['usgs_vcs']
            data['lat'] = row['usgs_lat']
            data['lon'] = row['usgs_lon']
            data['crs'] = row['usgs_crs']
        else:
            data['datum'] = row['nws_datum']
            data['vcs'] = row['nws_vcs']
            data['lat'] = row['nws_lat']
            data['lon'] = row['nws_lon']
            data['crs'] = row['nws_crs']

        # SPECIAL CASE: Custom workaround these sites have faulty crs from WRDS. CRS needed for NGVD29 conversion to NAVD88
        # USGS info indicates NAD83 for site: bgwn7, fatw3, mnvn4, nhpp1, pinn4, rgln4, rssk1, sign4, smfn7, stkn4, wlln7 
        # Assumed to be NAD83 (no info from USGS or NWS data): dlrt2, eagi1, eppt2, jffw3, ldot2, rgdt2
        if lid in ['bgwn7', 'dlrt2','eagi1','eppt2','fatw3','jffw3','ldot2','mnvn4','nhpp1','pinn4','rgdt2','rgln4','rssk1','sign4','smfn7','stkn4','wlln7' ]:
            data['crs'] = 'NAD83'
        # ___________________________________________________________________#
        
        # SPECIAL CASE: Workaround for bmbp1; CRS supplied by NRLDB is mis-assigned (NAD29) and is actually NAD27. 
        # This was verified by converting USGS coordinates (in NAD83) for bmbp1 to NAD27 and it matches NRLDB coordinates.
        if lid == 'bmbp1':
            data['crs'] = 'NAD27'
        # ___________________________________________________________________#
        
        # SPECIAL CASE: Custom workaround these sites have poorly defined vcs from WRDS. VCS needed to ensure datum reported in NAVD88. 
        # If NGVD29 it is converted to NAVD88.
        # bgwn7, eagi1 vertical datum unknown, assume navd88
        # fatw3 USGS data indicates vcs is NAVD88 (USGS and NWS info agree on datum value).
        # wlln7 USGS data indicates vcs is NGVD29 (USGS and NWS info agree on datum value).
        if lid in ['bgwn7','eagi1','fatw3']:
            data['vcs'] = 'NAVD88'
        elif lid == 'wlln7':
            data['vcs'] = 'NGVD29'
        # _________________________________________________________________________________________________________#
        
        # Adjust datum to NAVD88 if needed
        # Default datum_adj_ft to 0.0
        datum_adj_ft = 0.0
        crs = data.get('crs')
        if data.get('vcs') in ['NGVD29', 'NGVD 1929', 'NGVD,1929', 'NGVD OF 1929', 'NGVD']:
            # Get the datum adjustment to convert NGVD to NAVD.
            try:
                datum_adj_ft = _ngvd_to_navd_ft(datum_info=data, region='contiguous', session=session)
                if abs(datum_adj_ft) > 10:
                    raise Exception('HTTPSConnectionPool')
            except Exception as e:
                e = str(e)
                message = ''
                if 'HTTPSConnectionPool' in e:
                    try:
                        datum_adj_ft = _ngvd_to_navd_ft(datum_info=data, region='contiguous', session=session)
                        e = ''
                    except Exception as e2:
                        e = str(e2)

                if e:
                    message += 'NOAA VDatum adjustment error: '
                    
                    if 'Invalid projection' in e:
                        message += 'invalid projection; '
                    else:
                        message += 'reason unknown; '
                        print(f'VDatum error. Inputs: {data}. Error: {e}')
                    
                    full_df.loc[full_df['nws_station_id'] == lid.upper(), 'status'] += message
                    full_df.loc[full_df['nws_station_id'] == lid.upper(), 'mapped'] = False
                    print_progress(progress)
                    continue
        
        ### -- Concluded Datum Offset --- ###
        
        full_df.loc[full_df['nws_station_id'] == lid.upper(), 'datum_adj_ft'] = round(datum_adj_ft, 2)
        print_progress(progress)
    
    return full_df

def _ngvd_to_navd_ft(datum_info, region='contiguous', session=None):
    '''
    Given the lat/lon, retrieve the adjustment from NGVD29 to NAVD88 in feet. 
    Uses NOAA tidal API to get conversion factor. Requires that lat/lon is
    in NAD27 crs. If input lat/lon are not NAD27 then these coords are 
    reprojected to NAD27 and the reproject coords are used to get adjustment.
    There appears to be an issue when region is not in contiguous US.

    Parameters
    ----------
    lat : FLOAT
        Latitude.
    lon : FLOAT
        Longitude.

    Returns
    -------
    datum_adj_ft : FLOAT
        Vertical adjustment in feet, from NGVD29 to NAVD88, and rounded to nearest hundredth.

    '''
    #If crs is not NAD 27, convert crs to NAD27 and get adjusted lat lon
    if datum_info['crs'] != 'NAD27':
        lat, lon = _convert_latlon_datum(datum_info['lat'], datum_info['lon'], datum_info['crs'], 'NAD27')
    else:
        #Otherwise assume lat/lon is in NAD27.
        lat = datum_info['lat']
        lon = datum_info['lon']
    #Define url for datum API
    datum_url = 'https://vdatum.noaa.gov/vdatumweb/api/convert'     
    #Define parameters. Hard code most parameters to convert NGVD to NAVD.    
    params = {
        'lon': lon,               # Input Source X (Longitude or Easting or X) (required)
        'lat': lat,               # Input Source Y (Latitude or Northing or Y) (required)
        'region': region,         # Input Region (optional - default is "contigous")
        's_h_frame': 'NAD27',     # Input Source Horizontal Reference Frame (optional - default is "NAD83_2011")
        's_v_frame': 'NGVD29'     # Input Source Vertical Reference Frame (optional - default is "NAVD88")
    }
    #Call the API
    requestor = session if session else requests
    response = requestor.get(datum_url, params=params, verify=False)
    results = response.json()
    
    if 'errorCode' in results:
        raise Exception(results['message'])
    
    #Get adjustment in meters (NGVD29 to NAVD88)
    adjustment = results['t_z']
    #convert meters to feet
    adjustment_ft = round(float(adjustment) * 3.28084, 2)

    if abs(adjustment_ft) > 10:
        # This is an error, likely from overloading the API, thus retry
        adjustment_ft = _ngvd_to_navd_ft(datum_info, region, session)
    return adjustment_ft

def _convert_latlon_datum(lat, lon, src_crs, dest_crs):
    '''
    Converts latitude and longitude datum from a source CRS to a dest CRS 
    using geopandas and returns the projected latitude and longitude coordinates.

    Parameters
    ----------
    lat : FLOAT
        Input Latitude.
    lon : FLOAT
        Input Longitude.
    src_crs : STR
        CRS associated with input lat/lon. Geopandas must recognize code.
    dest_crs : STR
        Target CRS that lat/lon will be projected to. Geopandas must recognize code.

    Returns
    -------
    new_lat : FLOAT
        Reprojected latitude coordinate in dest_crs.
    new_lon : FLOAT
        Reprojected longitude coordinate in dest_crs.

    '''    
    #Create a temporary DataFrame containing the input lat/lon.
    temp_df = pd.DataFrame({'lat': [lat], 'lon': [lon]})
    #Convert dataframe to a GeoDataFrame using the lat/lon coords. Input CRS is assigned.
    temp_gdf = gpd.GeoDataFrame(temp_df, geometry=gpd.points_from_xy(temp_df.lon, temp_df.lat), crs=src_crs)
    #Reproject GeoDataFrame to destination CRS.
    reproject = temp_gdf.to_crs(dest_crs)
    #Get new Lat/Lon coordinates from the geometry data.
    new_lat,new_lon = [reproject.geometry.y.item(), reproject.geometry.x.item()]
    return new_lat, new_lon


def trigger_initialize_pipeline():
    """
        Triggers the db_ingest lambda function to ingest a specific file into the vizprocessing db.

        Args:
            bucket (str): The s3 bucket containing the file.
            s3_file_path (str): The s3 path to ingest into the db.
    """
    boto_config = botocore.client.Config(max_pool_connections=1, connect_timeout=60, read_timeout=600)
    lambda_client = boto3.client('lambda', config=boto_config)

    payload = {
        "configuration": "catfim",
        "reference_time": dt.datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
        "job_type": "auto"
    }
    print(payload)
    lambda_client.invoke(FunctionName=INITIALIZE_PIPELINE_FUNCTION,
                         InvocationType='Event',
                         Payload=json.dumps(payload))
    
def print_progress(progress):
    if progress:
        progress['counter'] += 1
        percent = round(100 * progress['counter'] / progress['total'])
        if percent and percent % 10 == 0 and percent not in progress['logged']:
            print(f"Progress: {percent}% complete")
            progress['logged'].append(percent)