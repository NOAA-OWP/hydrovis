import requests
import os
import pandas as pd
from datetime import datetime, timedelta
import boto3
import botocore
import json

from viz_lambda_shared_funcs import check_s3_file_existence

from es_logging import get_elasticsearch_logger
es_logger = get_elasticsearch_logger()

MAX_VALS_BUCKET = os.environ['MAX_VALS_BUCKET']
PROCESSED_OUTPUT_PREFIX = os.environ['PROCESSED_OUTPUT_PREFIX']
WRDS_HOST = os.environ["DATASERVICES_HOST"]
CACHE_DAYS = os.environ.get('CACHE_DAYS') if os.environ.get('CACHE_DAYS') else 30
INITIALIZE_PIPELINE_FUNCTION = os.environ['INITIALIZE_PIPELINE_FUNCTION']

s3 = boto3.client('s3')


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
    reference_date = datetime.strptime(event['time'], "%Y-%m-%dT%H:%M:%SZ")
    reference_time = reference_date.strftime("%Y-%m-%d %H:%M:%S")
    es_logger.info(f"Retrieving AHPS forecast data for reference time {event['time']}")

    df = get_recent_rfc_forecasts()

    missing_locations = df[df['latitude'].isna()].index.tolist()
    if missing_locations:
        df_locations = get_location_metadata(missing_locations)
        df.update(df_locations)

    df_meta = df.drop(columns=['members'])
    meta_key = f"{PROCESSED_OUTPUT_PREFIX}/{reference_date.strftime('%Y%m%d')}/{reference_date.strftime('%H')}_{reference_date.strftime('%M')}_ahps_metadata.csv"
    upload_df_to_s3(df_meta, MAX_VALS_BUCKET, meta_key)

    df_forecasts = extract_and_flatten_rfc_forecasts(df[['members']])
    forecast_key = f"{PROCESSED_OUTPUT_PREFIX}/{reference_date.strftime('%Y%m%d')}/{reference_date.strftime('%H')}_{reference_date.strftime('%M')}_ahps_forecasts.csv"
    upload_df_to_s3(df_forecasts, MAX_VALS_BUCKET, forecast_key)

    es_logger.info(f"Triggering DB ingest for ahps forecast and metadata for {reference_time}")
    trigger_db_ingest("ahps", reference_time, MAX_VALS_BUCKET, forecast_key)

    cleanup_cache(reference_date)

def get_recent_rfc_forecasts(hour_range=48):
    ahps_call = f"http://{WRDS_HOST}/api/rfc_forecast/v2.0/forecast/stage/nws_lid/all/?returnNewestForecast=true&excludePast=true&minForecastStatus=action"  # noqa
    print(f"Fetching AHPS forecast data from {ahps_call}")
    res = requests.get(ahps_call)

    print("Parsing forecast data")
    res = res.json()

    df = pd.DataFrame(res['forecasts'])
    df['issuedTime'] = pd.to_datetime(df['issuedTime'], format='%Y-%m-%dT%H:%M:%SZ')
    
    date_range = datetime.utcnow() - timedelta(hours=48)
    df = df[pd.to_datetime(df['issuedTime']) > date_range]

    df = pd.concat([df.drop(['location'], axis=1), df['location'].apply(pd.Series)], axis=1)
    df = pd.concat([df.drop(['names'], axis=1), df['names'].apply(pd.Series)], axis=1)
    df = pd.concat([df.drop(['nws_coordinates'], axis=1), df['nws_coordinates'].apply(pd.Series)], axis=1)
    df = df.drop(['units'], axis=1)
    df = pd.concat([df.drop(['thresholds'], axis=1), df['thresholds'].apply(pd.Series)], axis=1)

    rename_columns = {
        "action": "action_threshold",
        "minor": "minor_threshold",
        "moderate": "moderate_threshold",
        "major": "major_threshold",
        "record": "record_threshold",
        "stage": "unit",
        "nwsLid": "nws_lid",
        "usgsSiteCode": "usgs_sitecode",
        "nwsName": "nws_name",
        "usgsName": "usgs_name",
        "nwm_feature_id": "feature_id"
    }
    df = df.rename(columns=rename_columns)

    columns_to_keep = [
        "producer", "issuer", "issuedTime", "generationTime", "members", "nws_lid",
        "usgs_sitecode", "feature_id", "nws_name", "usgs_name", "latitude",
        "longitude", "units", "action_threshold", "minor_threshold", "moderate_threshold",
        "major_threshold", "record_threshold" 
    ]

    drop_columns = [column for column in df.columns if column not in columns_to_keep]
    df = df.drop(columns=drop_columns)

    df.loc[df['feature_id'].isnull(), 'feature_id'] = -9999
    df['feature_id'] = df['feature_id'].astype(int)

    df = df.set_index('nws_lid')
    
    df = df[[
        'producer', 'issuer', 'issuedTime', 'generationTime', 'members',
        'usgs_sitecode', 'feature_id', 'nws_name', 'usgs_name', 'latitude',
        'longitude', 'action_threshold', 'minor_threshold',
        'moderate_threshold', 'major_threshold', 'record_threshold', 'units'
    ]]
    
    return df

def get_location_metadata(nws_lid_list):
    nws_lid_list = ",".join(nws_lid_list)

    location_url = f"http://{WRDS_HOST}/api/location/v3.0/metadata/nws_lid/{nws_lid_list}"
    location_res = requests.get(location_url, verify=False)
    location_res = location_res.json()

    df_locations = pd.DataFrame(location_res['locations'])
    df_locations = pd.concat([df_locations.drop(['identifiers'], axis=1), df_locations['identifiers'].apply(pd.Series)], axis=1)
    df_locations = pd.concat([df_locations.drop(['nws_data'], axis=1), df_locations['nws_data'].apply(pd.Series)], axis=1)

    drop_columns = [
        'usgs_data', 'nwm_feature_data', 'env_can_gage_data', 'nws_preferred', 'usgs_preferred', 'goes_id', 'env_can_gage_id',
        'geo_rfc', 'map_link', 'horizontal_datum_name', 'county', 'county_code', 'huc', 'hsa',
        'zero_datum', 'vertical_datum_name', 'rfc_forecast_point', 'rfc_defined_fcst_point', 'riverpoint'
    ]
    rename_columns = {
        "usgs_site_code": "usgs_sitecode",
        "name": "usgs_name",
        "nwm_feature_id": "feature_id",
        "wfo": "issuer",
        "rfc": "producer",
        "issuedTime": "issued_time",
        "generationTime": "generation_time"
    }
    df_locations = df_locations.drop(columns=drop_columns)
    df_locations = df_locations.rename(columns=rename_columns)

    df_locations = df_locations.set_index("nws_lid")
    
    return df_locations

def extract_and_flatten_rfc_forecasts(df_forecasts):
    df_forecasts = pd.concat([df_forecasts.drop(['members'], axis=1), df_forecasts['members'].apply(pd.Series)], axis=1)
    df_forecasts = pd.concat([df_forecasts.drop([0], axis=1), df_forecasts[0].apply(pd.Series)], axis=1)
    df_forecasts = pd.concat([df_forecasts.drop(['dataPointsList'], axis=1), df_forecasts['dataPointsList'].apply(pd.Series)], axis=1)  # noqa

    forecasts = df_forecasts[0].apply(pd.Series).reset_index().melt(id_vars='nws_lid')
    forecasts = forecasts.dropna()[['nws_lid', 'value']].set_index('nws_lid')

    df_forecasts = pd.merge(df_forecasts, forecasts, left_index=True, right_index=True)

    df_forecasts = df_forecasts.drop(columns=[0, 'identifier', 'forecast_status'])

    df_forecasts = pd.concat([df_forecasts.drop(['value'], axis=1), df_forecasts['value'].apply(pd.Series)], axis=1)
    df_forecasts = df_forecasts.rename(columns={"value": "stage"})
    
    return df_forecasts

def upload_df_to_s3(df, bucket, key):
    print("Saving dataframe to csv output")
    tmp_csv = f"/tmp/{os.path.basename(key)}"
    df.to_csv(tmp_csv)
    
    es_logger.info(f"Uploading csv to {key}")
    s3.upload_file(
        tmp_csv, bucket, key,
        ExtraArgs={'ServerSideEncryption': 'aws:kms'}
    )
    os.remove(tmp_csv)

def cleanup_cache(reference_date, buffer_days=.25):
    """
        Cleans up old max flows files that are beyond the cache

        Args:
            configuration(str): The configuration for the forecast being processed
            date(str): The date for the forecast being processed
            short_hand_config(str): The short-hand NWM configuration for the forecast being processed
            hour(str): The hour for the forecast being processed
            buffer_days(int): The number of days of max flows files to keep
    """
    print(f"Cleaning up files older than {CACHE_DAYS} days")
    s3_resource = boto3.resource('s3')

    # Determine the date threshold for keeping max flows files
    buffer_increments = int(buffer_days*24*4)
    cache_date = reference_date - timedelta(days=int(CACHE_DAYS))

    # Loop through the buffer hours to try to delete old files, starting from the cache_date
    for fifteen_min_increments in range(1, buffer_increments+1):
        buffer_date = cache_date - timedelta(minutes=15*fifteen_min_increments)

        metadata_csv_key = f"{PROCESSED_OUTPUT_PREFIX}/{buffer_date.strftime('%Y%m%d')}/{buffer_date.strftime('%H')}_{buffer_date.strftime('%M')}_ahps_metadata.csv"  # noqa
        forecast_csv_key = f"{PROCESSED_OUTPUT_PREFIX}/{buffer_date.strftime('%Y%m%d')}/{buffer_date.strftime('%H')}_{buffer_date.strftime('%M')}_ahps_forecasts.csv"  # noqa

        if check_s3_file_existence(MAX_VALS_BUCKET, metadata_csv_key):
            s3_resource.Object(MAX_VALS_BUCKET, metadata_csv_key).delete()
            print(f"Deleted file {metadata_csv_key} from {MAX_VALS_BUCKET}")

        if check_s3_file_existence(MAX_VALS_BUCKET, forecast_csv_key):
            s3_resource.Object(MAX_VALS_BUCKET, forecast_csv_key).delete()
            print(f"Deleted file {forecast_csv_key} from {MAX_VALS_BUCKET}")


def trigger_db_ingest(configuration, reference_time, bucket, s3_file_path):
    """
        Triggers the db_ingest lambda function to ingest a specific file into the vizprocessing db.

        Args:
            configuration(str): The configuration for the forecast being processed
            reference_time (datetime): The reference time of the originating forecast
            bucket (str): The s3 bucket containing the file.
            s3_file_path (str): The s3 path to ingest into the db.
    """
    boto_config = botocore.client.Config(max_pool_connections=1, connect_timeout=60, read_timeout=600)
    lambda_client = boto3.client('lambda', config=boto_config)

    payload = {"data_key": s3_file_path, "data_bucket": bucket, "invocation_type": "event"}
    print(payload)
    lambda_client.invoke(FunctionName=INITIALIZE_PIPELINE_FUNCTION,
                         InvocationType='Event',
                         Payload=json.dumps(payload))
