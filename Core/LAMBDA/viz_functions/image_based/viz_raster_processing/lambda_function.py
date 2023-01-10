import boto3
import os
import rioxarray as rxr
from rasterio.crs import CRS
from datetime import datetime
import requests
from viz_classes import s3_file

OUTPUT_BUCKET = os.environ['OUTPUT_BUCKET']
OUTPUT_PREFIX = os.environ['OUTPUT_PREFIX']

class MissingS3FileException(Exception):
    """ my custom exception class """

def lambda_handler(event, context):
    service_name = event['service']['service']
    try:
        func = getattr(__import__(f"services.{service_name}", fromlist=["main"]), "main")
    except AttributeError:
        raise Exception(f'function not found {service_name}')

    uploaded_rasters = func(event['service'], event['reference_time'])

    event['output_rasters'] = uploaded_rasters
    event['output_bucket'] = OUTPUT_BUCKET
    
    del event['service']['input_files']
    del event['service']['bucket']
        
    return event

def open_raster(bucket, file, variable):
    print(f"Opening {variable} in raster for {file}")
    s3 = boto3.client('s3')

    file = check_if_file_exists(bucket, file)
    download_path = f'/tmp/{os.path.basename(file)}'
    print(f"--> Downloading {file} to {download_path}")
    if 'https://storage.googleapis.com/national-water-model' in file:
        open(download_path, 'wb').write(requests.get(file, allow_redirects=True).content)
    else:
        s3.download_file(bucket, file, download_path)

    ds = rxr.open_rasterio(download_path)
    
    os.remove(download_path)
    
    return ds[variable]

def create_raster(data, crs):
    print(f"Creating raster for {data.name}")
    data.rio.write_crs(crs, inplace=True)
    data.rio.write_nodata(0, inplace=True)
    if "grid_mapping" in data.attrs:
        data.attrs.pop("grid_mapping")
        
    if "_FillValue" in data.attrs:
        data.attrs.pop("_FillValue")

    local_raster = f'/tmp/{data.name}.tif'

    print(f"Saving raster to {local_raster}")
    data.rio.to_raster(local_raster)
    
    return local_raster

def upload_raster(reference_time, local_raster, service_name, raster_name):
    reference_date = datetime.strptime(reference_time, "%Y-%m-%d %H:%M:%S")
    date = reference_date.strftime("%Y%m%d")
    hour = reference_date.strftime("%H")
    
    s3_raster_key = f"{OUTPUT_PREFIX}/{service_name}/{date}/{hour}/workspace/tif/{raster_name}.tif"
    
    print(f"--> Uploading raster to s3://{OUTPUT_BUCKET}/{s3_raster_key}")
    s3 = boto3.client('s3')
    
    s3.upload_file(local_raster, OUTPUT_BUCKET, s3_raster_key)
    os.remove(local_raster)

    return s3_raster_key

def sum_rasters(bucket, input_files, variable):
    print(f"Adding {variable} variable of {len(input_files)} raster(s)...")
    sum_initiated = False
    for input_file in input_files:
        print(f"Adding {input_file}...")
        data = open_raster(bucket, input_file, variable)
        time_index = 0
        if len(data.time) > 1:
            time_index = -1
            for i, t in enumerate(data.time):
                if str(float(data.sel(time=t)[0][0])) != 'nan':
                    time_index = i
                    break
            if (time_index < 0):
                raise Exception(f"No valid time steps were found in file: {input_file}")
        
        if not sum_initiated:
            data_sum = data.sel(time=data.time[time_index])
            crs = CRS.from_proj4(data.proj4)
            sum_initiated = True
        else:
            data_sum += data.sel(time=data.time[time_index])
    print("Done adding rasters!")
    return data_sum, crs

def check_if_file_exists(bucket, file):
    file_source = 'Google' if 'https://storage.googleapis.com/national-water-model' in file else 'S3'
    if file_source == 'S3':
        if s3_file(bucket, file).check_existence():
            print("File exists on S3.")
            return file
        elif requests.head(file.replace('common/data/model/com/nwm/prod', 'https://storage.googleapis.com/national-water-model')).status_code == 200:
            print("File does not exist on S3 (even though it should), but does exists on Google Cloud.")
            return file.replace('common/data/model/com/nwm/prod', 'https://storage.googleapis.com/national-water-model')
        else:
            raise MissingS3FileException(f"{file} does not exist on S3.")
    elif file_source == 'Google':
        if requests.head(file).status_code == 200:
            print("File exists on Google Cloud.")
            return file
        else:
            raise Exception(f"Google Cloud file doesn't seem to exist: {file}")
