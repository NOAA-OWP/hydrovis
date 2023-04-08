import boto3
import os
import rioxarray as rxr
from rasterio.crs import CRS
from datetime import datetime
from viz_lambda_shared_funcs import check_if_file_exists, generate_file_list

OUTPUT_BUCKET = os.environ['OUTPUT_BUCKET']
OUTPUT_PREFIX = os.environ['OUTPUT_PREFIX']

def lambda_handler(event, context):
    product_name = event['product']['product']

    file_pattern = event['product']['raster_input_files']['file_format']
    file_step = event['product']['raster_input_files']['file_step']
    file_window = event['product']['raster_input_files']['file_window']
    bucket = event['product']['raster_input_files']['bucket']
    reference_time = event['reference_time']
    reference_date = datetime.strptime(reference_time, "%Y-%m-%d %H:%M:%S")

    file_step = None if file_step == "None" else file_step
    file_window = None if file_window == "None" else file_window
    
    input_files = generate_file_list(file_pattern, file_step, file_window, reference_date)

    try:
        func = getattr(__import__(f"products.{product_name}", fromlist=["main"]), "main")
    except AttributeError:
        raise Exception(f'function not found {product_name}')

    uploaded_rasters = func(product_name, bucket, input_files, reference_time)
        
    return {
        "output_rasters": uploaded_rasters,
        "output_bucket": OUTPUT_BUCKET
    }

def open_raster(bucket, file, variable):
    download_path = check_if_file_exists(bucket, file, download=True)
    print(f"--> Downloaded {file} to {download_path}")
    
    print(f"Opening {variable} in raster for {file}")
    ds = rxr.open_rasterio(download_path, variable=variable)
    
    # for some files like NBM alaska, the line above opens the attribute itself
    try:
        data = ds[variable]
    except:
        data = ds
        
    
    if "alaska" in file:
        proj4 = "+proj=stere +lat_0=90 +lat_ts=60 +lon_0=-135 +x_0=0 +y_0=0 +R=6370000 +units=m +no_defs"
    else:
        try:
            proj4 = data.proj4
        except:
            proj4 = ds.proj4
            
    crs = CRS.from_proj4(proj4)

    os.remove(download_path)
    
    return [data, crs]

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

def upload_raster(reference_time, local_raster, product_name, raster_name):
    reference_date = datetime.strptime(reference_time, "%Y-%m-%d %H:%M:%S")
    date = reference_date.strftime("%Y%m%d")
    hour = reference_date.strftime("%H")
    
    s3_raster_key = f"{OUTPUT_PREFIX}/{product_name}/{date}/{hour}/workspace/tif/{raster_name}.tif"
    
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
        data, crs = open_raster(bucket, input_file, variable)
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
            sum_initiated = True
        else:
            data_sum += data.sel(time=data.time[time_index])
    print("Done adding rasters!")
    return data_sum, crs
