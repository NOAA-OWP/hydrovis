import sys
import os
sys.path.append("../utils")
from lambda_function import open_raster, sum_rasters, create_raster, upload_raster

def main(service_data, reference_time):
    bucket = service_data["bucket"]
    input_files = service_data["input_files"]
    service_name = service_data['service']

    ### ABOVE THIS WILL BE THE SAME

    variable = "SNEQV"
    data_temp, crs = open_raster(bucket, input_files[0], variable)
    #data, crs = open_raster(bucket, reversed_input_files[0], variable)
    data_nan = data_temp.where(data_temp != -99990)
    data = data_nan / 254  #Convert kg/m2 to in, conversion should be 25.4
                        #but there's an extra order of mag on the original raster, don't know why
    data = data.round(2)


    ### BELOW THIS WILL BE THE SAME
    local_raster = create_raster(data, crs)
    raster_name = service_name
    uploaded_raster = upload_raster(reference_time, local_raster, service_name, raster_name)

    return [uploaded_raster] 
