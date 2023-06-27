import sys
sys.path.append("../utils")
from lambda_function import open_raster, create_raster, upload_raster

def main(product_name, data_bucket, input_files, reference_time, output_bucket, output_workspace):
    variable = "SNEQV"

    data_temp, crs = open_raster(data_bucket, input_files[0], variable)
    data_nan = data_temp.where(data_temp != -99990)
    data = data_nan / 254  #Convert kg/m2 to in, conversion should be 25.4 but there's an extra order of mag on the original raster, don't know why
    data = data.round(2)

    local_raster = create_raster(data, crs, product_name)
    uploaded_raster = upload_raster(local_raster, output_bucket, output_workspace)

    return [uploaded_raster]
