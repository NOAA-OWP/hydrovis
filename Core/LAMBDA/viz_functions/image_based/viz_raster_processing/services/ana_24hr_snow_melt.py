import sys
import os
sys.path.append("../utils")
from lambda_function import open_raster, sum_rasters, create_raster, upload_raster

def main(service_data, reference_time):
    # assign variables
    bucket = service_data["bucket"]
    input_files = service_data["input_files"]
    service_name = service_data['service']
    reversed_input_files = sorted(input_files, reverse=True)
    variable = "SNEQV"

    # get the two land files from today and yesterday (24 hours apart)
    current_snow, crs = open_raster(bucket, reversed_input_files[0], variable)
    past_snow, crs = open_raster(bucket, reversed_input_files[1], variable)

    # format the missing error coded fields with NaN
    current_snow_nan = current_snow.where(current_snow != -99990)
    current = current_snow_nan / 254  #Convert kg/m2 to in, moving decimal right once
    past_snow_nan = past_snow.where(past_snow != -99990)
    past = past_snow_nan / 254  #Convert kg/m2 to in, moving decimal right once

    # get the difference between yesterdays snow depth and todays
    snow_difference = past - current

    # remove any values that are negative - leaving only values where snow decreased, or melted
    make_snow_difference = snow_difference.where(snow_difference > 0, snow_difference, 0)

    # finalize raster
    local_raster = create_raster(data, crs)
    raster_name = service_name
    uploaded_raster = upload_raster(reference_time, local_raster, service_name, raster_name)

    return [uploaded_raster] 
