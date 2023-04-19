import sys
import os
sys.path.append("../utils")
from lambda_function import open_raster, sum_rasters, create_raster, upload_raster

def main(service_data, reference_time):
    bucket = service_data["bucket"]
    input_files = service_data["input_files"]
    service_name = service_data['service']

    variable = "SOILICE"
    data_temp, crs = open_raster(bucket, input_files[0], variable)
    data_nan = data_temp.where(data_temp != -999900)
    data = data_nan/100  
    data = data.round(2)

    local_raster = create_raster(data, crs)
    raster_name = service_name
    uploaded_raster = upload_raster(reference_time, local_raster, service_name, raster_name)

    return [uploaded_raster]
