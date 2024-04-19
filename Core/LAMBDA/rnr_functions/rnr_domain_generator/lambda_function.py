import os
import boto3
import datetime as dt
import numpy as np
import shutil
import sys
import tempfile
import xarray as xr
from viz_classes import database

OUTPUT_BUCKET = os.getenv('OUTPUT_BUCKET')
OUTPUT_PREFIX = os.getenv('OUTPUT_PREFIX')

DT_FORMAT = '%Y%m%d%H%M'
FILE_TYPES = [
    'timeslices', 
    'nudgingparams', 
    'routelink', 
    'lakeparm', 
    'gwbuckparm',
    'forcing',
    'restart'
]

s3 = boto3.client('s3')

def lambda_handler(event, context):
    step = event['step']
    viz_db = database(db_type="viz")
    with open(f'sql/{step}.sql') as f:
        sql = f.read().replace('%', '%%')

    if step == 'domain':
        print(f'Executing {step}.sql...')
        
        connection = viz_db.get_db_connection()
        with connection:
            with connection.cursor() as cur:
                cur.execute(sql)
                result = cur.fetchone()
        connection.close()

        reference_time = dt.datetime.strptime(result[0], '%Y-%m-%d %H:%M:%S UTC').strftime(DT_FORMAT)
        run_time_obj = dt.datetime.strptime(event['run_time'], '%Y-%m-%dT%H:%M:%SZ')
        run_time = run_time_obj.strftime(DT_FORMAT)
        
        return {
            'reference_time': reference_time,
            'run_time': run_time,
            'domain_file_types': FILE_TYPES
        }
    
    if step in FILE_TYPES:
        temp_dpath = tempfile.mkdtemp()
        key_prefix = f'{OUTPUT_PREFIX}/{event["reference_time"]}/{event["run_time"]}'
        reference_time = dt.datetime.strptime(event['reference_time'], DT_FORMAT)
        sql_reftime = reference_time.strftime('%Y-%m-%dT%H:%M:%SZ')
        sql = sql.replace('CURRENT_DATE', f"'{sql_reftime}'")
        print(f'Executing {step}.sql...')
        df = viz_db.run_sql_in_db(sql)
        func_name = f'create_{step}'
        func = getattr(sys.modules[__name__], func_name)
        
        print(f'Executing {func_name} function...')
        func(df, temp_dpath, reference_time, key_prefix)
        
    else:
        raise Exception(f"Invalid step: {step}")
    
    shutil.rmtree(temp_dpath)

def create_timeslices(df, workdir, reference_time, key_prefix):
    new_df = df.groupby('stationId').apply(lambda x: x.set_index('time').interpolate(method='time'))
    new_df = new_df.groupby('time')
    for time, iter_df in new_df:
        t = time.strftime('%Y-%m-%d_%H:%M:%S')
        fname =  f'{t}.15min.usgsTimeSlice.ncdf'
        fpath = os.path.join(workdir, fname)
        iter_df['time'] = t
        iter_df['stationIdInd'] = list(range(len(iter_df.stationId)))
        ds = iter_df.set_index('stationIdInd').to_xarray()
        ds = ds.drop_vars('stationIdInd')
        ds.attrs = {
            'sliceTimeResolutionMinutes': "15",
            'fileUpdateTimeUTC': t,
            'sliceCenterTimeUTC': t
        }
        ds.to_netcdf(fpath, format="NETCDF4_CLASSIC", encoding={
            "queryTime": {"dtype": "int32"},
            "discharge_quality": {"dtype": "int16"},
            "discharge": {"dtype": "float32"},
            "time": {"dtype": "|S19", "char_dim_name": "timeStrLen"},
            "stationId": {"dtype": "|S15", "char_dim_name": "stationIdStrLen"},
        }, unlimited_dims=["stationIdInd"])
        key = f'{key_prefix}/nudgingTimeSliceObs/{fname}'
        s3.upload_file(fpath, OUTPUT_BUCKET, key)

def create_nudgingparams(df, workdir, reference_time, key_prefix):
    fname =  f'nudgingParams.nc'
    fpath = os.path.join(workdir, fname)
    num_gages = len(df.stationId)
    ds = xr.Dataset({
        'G': (("stationIdInd"), [1] * num_gages),
        'R': (("stationIdInd"), [0.25] * num_gages),
        'tau': (("stationIdInd"), [dt.timedelta(minutes=15)] * num_gages),
        'expCoeff': (("stationIdInd", "monthInd", "threshCatInd"), np.full((num_gages, 12, 2), fill_value=dt.timedelta(minutes=120))),
        'qThresh': (("stationIdInd", "monthInd", "threshInd"), np.full((num_gages, 12, 1), fill_value=-100)),
        'stationId': (("stationIdInd"), df.stationId.values)
    }, attrs={
        'history': 'not set',
        'NCO': 'not set',
        'Source_software': "AWS Lambda function: rnr_preprocess"
    })

    ds.to_netcdf(fpath, format="NETCDF4_CLASSIC", encoding={
        "G": {"dtype": "float32"},
        "R": {"dtype": "float32"},
        "tau": {"dtype": "float32", "units": "minutes"},  # Actually timedelta64[ns], but stored as float32
        "expCoeff": {"dtype": "float32", "units": "minutes"},  # Actually timedelta64[ns], but stored as float32
        "qThresh": {"dtype": "float32"},
        "stationId": {"dtype": "|S15", "char_dim_name": "stationIdStrLen"}
    }, unlimited_dims=['stationIdInd'])

    key = f'{key_prefix}/DOMAIN/{fname}'
    s3.upload_file(fpath, OUTPUT_BUCKET, key)

def create_routelink(df, workdir, reference_time, key_prefix):
    fname =  'RouteLink.nc'
    fpath = os.path.join(workdir, fname)
    ds = df.to_xarray()
    ds['gages'] = ds.gages_trim
    ds = ds.drop_vars(['index', 'order_index', 'gages_trim'])
    ds = ds.rename_dims({'index': 'feature_id'})
    ds = ds.set_coords(("lon", "lat"))
    ds['time'] = ds['time'][0]
    ds.attrs = {
        "Source_software":   "AWS Lambda function: rnr_preprocess",
        "Convention":        "CF-1.6",
        "featureType":       "timeSeries",
        "processing_notes":  "None",
        "region":            "CONUS",
        "NCO":               "netCDF Operators version 4.7.9",
        "version":           "NWM v2.1"
    }
    ds.to_netcdf(fpath, format="NETCDF4_CLASSIC", encoding={
        "link": {"dtype": "int32"},
        "from": {"dtype": "int32"},
        "to": {"dtype": "int32"},
        "lon": {"dtype": "float32"},
        "lat": {"dtype": "float32"},
        "alt": {"dtype": "float32"},
        "order": {"dtype": "int32"},
        "Qi": {"dtype": "float32"},
        "MusK": {"dtype": "float32"},
        "MusX": {"dtype": "float32"},
        "Length": {"dtype": "float32"},
        "n": {"dtype": "float32"},
        "So": {"dtype": "float32"},
        "ChSlp": {"dtype": "float32"},
        "BtmWdth": {"dtype": "float32"},
        "NHDWaterbodyComID": {"dtype": "int32"},
        "time": {"dtype": "float32"},  # Actually timedelta64[ns], but stored as float32
        "gages": {"dtype": "|S15", "char_dim_name": "IDLength"},
        "Kchan": {"dtype": "int16"},
        "ascendingIndex": {"dtype": "int32"},
        "nCC": {"dtype": "float32"},
        "TopWdthCC": {"dtype": "float32"},
        "TopWdth": {"dtype": "float32"}
    })
    key = f'{key_prefix}/DOMAIN/{fname}'
    s3.upload_file(fpath, OUTPUT_BUCKET, key)

def create_lakeparm(df, workdir, reference_time, key_prefix):
    fname =  'LAKEPARM.nc'
    fpath = os.path.join(workdir, fname)
    ds = df.to_xarray()
    ds = ds.drop_vars(['index', 'order_index', 'crs'])
    ds = ds.rename_dims({'index': 'feature_id'})
    ds = ds.set_coords(("lon", "lat"))
    ds.attrs = {
        "Source_software":   "AWS Lambda function: rnr_preprocess",
        "Convention":        "CF-1.5",
        "featureType":       "timeSeries",
        "processing_notes":  "None",
        "region":            "CONUS",
        "NCO":               "netCDF Operators version 4.7.9",
        "version":           "NWM v2.1"
    }
    ds.to_netcdf(fpath, format="NETCDF4_CLASSIC", encoding={
        "Dam_Length": {"dtype": "int32"},
        "LkMxE": {"dtype": "float64"},
        "OrificeE": {"dtype": "float64"},
        "WeirE": {"dtype": "float64"},
        "lake_id": {"dtype": "int32"},
        "LkArea": {"dtype": "float64"},
        "WeirC": {"dtype": "float64"},
        "WeirL": {"dtype": "float64"},
        "OrificeC": {"dtype": "float64"},
        "OrificeA": {"dtype": "float64"},
        "lat": {"dtype": "float32"},
        "lon": {"dtype": "float32"},
        "time": {"dtype": "float32"},
        "ascendingIndex": {"dtype": "int32"},
        "ifd": {"dtype": "float32"}
    })
    key = f'{key_prefix}/DOMAIN/{fname}'
    s3.upload_file(fpath, OUTPUT_BUCKET, key)

def create_gwbuckparm(df, workdir, reference_time, key_prefix):
    fname =  'GWBUCKPARM.nc'
    fpath = os.path.join(workdir, fname)
    ds = df.to_xarray()
    ds = ds.drop_vars(['index'])
    ds = ds.rename_dims({'index': 'BasinDim'})
    ds.attrs = {
        "Source_software":   "AWS Lambda function: rnr_preprocess",
        "missing_values":    -999999.0
    }
    ds.to_netcdf(fpath, format="NETCDF4_CLASSIC", encoding={
        "Area_sqkm": {"dtype": "float32"},
        "Basin": {"dtype": "float64"},
        "ComID": {"dtype": "float64"},
        "Expon": {"dtype": "float32"},
        "Zinit": {"dtype": "float32"},
        "Zmax": {"dtype": "float32"},
        "Coeff": {"dtype": "float32"}
    })
    key = f'{key_prefix}/DOMAIN/{fname}'
    s3.upload_file(fpath, OUTPUT_BUCKET, key)

def create_forcing(df, workdir, reference_time, key_prefix):
    ref_time_for_fname = reference_time.strftime(DT_FORMAT)
    fname =  f'{ref_time_for_fname}.CHRTOUT_DOMAIN1'
    ref_time_for_attrs = reference_time.strftime('%Y-%m-%d_00:00:00')
    fpath = os.path.join(workdir, fname)
    ds = df.to_xarray()
    ds = ds.drop_vars(['index'])
    ds = ds.swap_dims({'index': 'feature_id'})
    ds['time'] = reference_time
    ds = ds.set_coords('time')
    ds['time'] = ds.time.expand_dims('time')
    ds.attrs = {
        "model_initialization_time": ref_time_for_attrs,
        "model_output_valid_time": ref_time_for_attrs,
        "stream_order_output": 1,
        "cdm_datatype": "Station",
        "Conventions": "Unidata Observation Dataset v1.0",
        "OVRTSWCRT": 1,
        "NOAH_TIMESTEP": 3600,
        "channel_only": 1,
        "channelBucket_only": 0,
        "station_dimension": "feature_id",
        "missing_value": -999999.0,
        "Source_software": "AWS Lambda function: rnr_preprocess",
        "_CoordSysBuilder": "ucar.nc2.dataset.conv.UnidataObsConvention"
    }
    ds.to_netcdf(fpath, format="NETCDF4_CLASSIC", encoding={
        "feature_id": {"dtype": "float64"},
        "streamflow": {"dtype": "float32"},
        "nudge": {"dtype": "float32"},
        "velocity": {"dtype": "float32"},
        "qSfcLatRunoff": {"dtype": "float32"},
        "qBucket": {"dtype": "float32"}
    })
    key = f'{key_prefix}/FORCING/{fname}'
    s3.upload_file(fpath, OUTPUT_BUCKET, key)

def create_restart(df, workdir, reference_time, key_prefix):
    ftime = reference_time.strftime('%Y-%m-%d_%H:%M')
    fname =  f'HYDRO_RST.{ftime}_DOMAIN1'
    fpath = os.path.join(workdir, fname)
    q_df = df[['qlink1', 'qlink2']]
    r_df = df[['resht', 'qlakeo']][~(df.resht.isna() & df.qlakeo.isna())]
    ds = q_df.to_xarray()
    ds = ds.drop_vars(['index'])
    ds = ds.rename_dims({'index': 'links'})
    ds['resht'] = r_df['resht']
    ds['qlakeo'] = r_df['qlakeo']
    ds = ds.drop_vars(['dim_0'])
    ds = ds.rename_dims({'dim_0': 'lakes'})
    md_time = reference_time.strftime('%Y-%m-%d_00:00:00')

    ds.attrs = {
        'his_out_counts': 1,
        'Restart_Time': md_time,
        'Since_Date': md_time,
        'DTCT': "300.f",
        'channel_only': 1,
        'channelBucket_only': 0,
        'Source_software': 'AWS Lambda function: rnr_preprocess',
        '_CoordSysBuilder': 'ucar.nc2.dataset.conv.DefaultConvention'
    }

    ds.to_netcdf(fpath, format="NETCDF4_CLASSIC", encoding={
        "qlink1": {"dtype": "float32"},
        "qlink2": {"dtype": "float32"},
        "resht": {"dtype": "float32"},
        "qlakeo": {"dtype": "float32"}
    })
    key = f'{key_prefix}/restart/{fname}'
    s3.upload_file(fpath, OUTPUT_BUCKET, key)
