import sys
import os
sys.path.append("../utils")
from lambda_function import open_raster, sum_rasters, create_raster, upload_raster

def main(service_data, reference_time):
    bucket = service_data["bucket"]
    input_files = service_data["input_files"]
    service_name = service_data['service']
    
    all_uploaded_rasters = []

    ###########################
    ## Day 1 Hourly Precip ##
    ###########################
    hour_intervals = [[1, 3], [4, 6], [7, 9], [10, 12], [13, 24]]
    
    daily_sum_initiated = False
    for hours in hour_intervals:
        hour1 = hours[0]-1
        hour2 = hours[1]
    
        data_sum, crs = sum_rasters(bucket, input_files[hour1:hour2], "RAINRATE")
        
        data_sum = data_sum * 3600 / 25.4
        data_sum = data_sum.round(2)

        if not daily_sum_initiated:
            daily_sum_initiated = True
            daily_sum = data_sum
        else:
            daily_sum += data_sum
        
        data_sum = data_sum.where(data_sum>0.01)
        local_raster = create_raster(data_sum, crs)
        
        raster_name = f"{hours[0]}hour-{hours[1]}hour_accum_precipitation"

        uploaded_raster = upload_raster(reference_time, local_raster, service_name, raster_name)
        all_uploaded_rasters.append(uploaded_raster)

    ##########################
    ## Day 1 Total Precip ##
    ##########################
    total_sum = daily_sum
    daily_sum = daily_sum.where(total_sum>0.01)
    local_raster = create_raster(daily_sum, crs)
    raster_name = "1hour-24hour_accum_precipitation"

    uploaded_raster = upload_raster(reference_time, local_raster, service_name, raster_name)
    all_uploaded_rasters.append(uploaded_raster)
    
    ###########################
    ## Day 2 Hourly Precip ##
    ###########################
    hour_intervals = [[25, 36], [37, 48]]
    
    daily_sum_initiated = False
    for hours in hour_intervals:
        hour1 = hours[0]-1
        hour2 = hours[1]
    
        data_sum, crs = sum_rasters(bucket, input_files[hour1:hour2], "RAINRATE")
        
        data_sum = data_sum * 3600 / 25.4
        data_sum = data_sum.round(2)

        if not daily_sum_initiated:
            daily_sum_initiated = True
            daily_sum = data_sum
        else:
            daily_sum += data_sum
        
        data_sum = data_sum.where(data_sum>0.01)
        local_raster = create_raster(data_sum, crs)
        
        raster_name = f"{hours[0]}hour-{hours[1]}hour_accum_precipitation"

        uploaded_raster = upload_raster(reference_time, local_raster, service_name, raster_name)
        all_uploaded_rasters.append(uploaded_raster)

    ##########################
    ## Day 2 Total Precip ##
    ##########################
    total_sum += daily_sum
    daily_sum = daily_sum.where(total_sum>0.01)
    local_raster = create_raster(daily_sum, crs)
    raster_name = "24hour-48hour_accum_precipitation"

    uploaded_raster = upload_raster(reference_time, local_raster, service_name, raster_name)
    all_uploaded_rasters.append(uploaded_raster)
    
    ##########################
    ## Forecast Total Precip ##
    ##########################
    total_sum = total_sum.where(total_sum>0.01)
    local_raster = create_raster(total_sum, crs)
    raster_name = "1hour-48hour_accum_precipitation"

    uploaded_raster = upload_raster(reference_time, local_raster, service_name, raster_name)
    all_uploaded_rasters.append(uploaded_raster)
    
    return all_uploaded_rasters
