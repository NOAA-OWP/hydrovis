import sys
sys.path.append("../utils")
from lambda_function import open_raster, create_raster, upload_raster

def main(product_name, data_bucket, input_files, reference_time, output_bucket, output_workspace):
    # assign variables
    reversed_input_files = sorted(input_files, reverse=True)
    variable = "SNEQV"

    # get the two land files from today and yesterday (24 hours apart)
    current_snow, crs = open_raster(data_bucket, reversed_input_files[0], variable)
    past_snow, crs = open_raster(data_bucket, reversed_input_files[1], variable)

    current_snow = current_snow.sel(time = current_snow.time[0])
    past_snow = past_snow.sel(time = past_snow.time[0])

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
    local_raster = create_raster(make_snow_difference, crs, product_name)

    uploaded_raster = upload_raster(local_raster, output_bucket, output_workspace)

    return [uploaded_raster]
