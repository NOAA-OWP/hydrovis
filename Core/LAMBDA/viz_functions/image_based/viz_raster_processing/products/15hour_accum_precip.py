import sys
sys.path.append("..")
from lambda_function import sum_rasters, create_raster, upload_raster

def main(product_name, data_bucket, input_files, reference_time):
    hour_intervals = [[1, 1], [2, 2], [3, 3], [4, 6], [7, 9], [10, 12], [13, 15]]
    
    ###################
    ## Hourly Precip ##
    ###################

    total_sum_initiated = False
    all_uploaded_rasters = []
    for hours in hour_intervals:
        hour1 = hours[0]-1
        hour2 = hours[1]
    
        data_sum, crs = sum_rasters(data_bucket, input_files[hour1:hour2], "RAINRATE")
        
        data_sum = data_sum * 3600 / 25.4
        data_sum = data_sum.round(2)

        if not total_sum_initiated:
            total_sum_initiated = True
            total_sum = data_sum
        else:
            total_sum += data_sum
        
        data_sum = data_sum.where(data_sum>0.01)
        local_raster = create_raster(data_sum, crs)
        
        if hours[0] == hours[1]:
            raster_name = f"{hours[0]}hour_accum_precipitation"
        else:
            raster_name = f"{hours[0]}hour-{hours[1]}hour_accum_precipitation"

        uploaded_raster = upload_raster(reference_time, local_raster, product_name, raster_name)
        all_uploaded_rasters.append(uploaded_raster)

    ###################
    ## Total Precip ##
    ###################
    total_sum = total_sum.where(total_sum>0.01)
    local_raster = create_raster(total_sum, crs)
    raster_name = "1hour-15hour_accum_precipitation"

    uploaded_raster = upload_raster(reference_time, local_raster, product_name, raster_name)
    all_uploaded_rasters.append(uploaded_raster)

    return all_uploaded_rasters
