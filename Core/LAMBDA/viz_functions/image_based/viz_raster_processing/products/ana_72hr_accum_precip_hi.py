import sys
import os
sys.path.append("../utils")
from lambda_function import open_raster, sum_rasters, create_raster, upload_raster

def main(service_data, reference_time):
    bucket = service_data["bucket"]
    input_files = service_data["input_files"]
    service_name = service_data['service']
    reversed_input_files = sorted(input_files, reverse=True)
    
    all_uploaded_rasters = []

    ###########################
    ## Past 72 Hour Precip in intervals ##
    ###########################
    
    hour_intervals = [[1, 1], [2, 3], [4, 6], [7, 12], [13, 24], [25, 48], [49, 72]]
    total_sum = None
    for hours in hour_intervals:
        hour1 = hours[0]-1
        hour2 = hours[1]
    
        data_sum, crs = sum_rasters(bucket, reversed_input_files[hour1:hour2], "RAINRATE")
        
        data_sum = data_sum * 3600 / 25.4
        data_sum = data_sum.round(2)

        if total_sum is None:
            total_sum = data_sum
        else:
            total_sum += data_sum
        
        filtered_sum = total_sum.where(total_sum>0.01)
        local_raster = create_raster(filtered_sum, crs)
        
        raster_name = f"past_{hour2}hour_accum_precipitation"

        uploaded_raster = upload_raster(reference_time, local_raster, service_name, raster_name)
        all_uploaded_rasters.append(uploaded_raster)
    
    return all_uploaded_rasters
