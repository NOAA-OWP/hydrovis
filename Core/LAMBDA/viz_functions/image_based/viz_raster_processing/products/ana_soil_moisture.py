import sys
sys.path.append("../utils")
from lambda_function import open_raster, create_raster, upload_raster

def main(product_name, data_bucket, input_files, reference_time):
    variable = "SOILSAT_TOP"

    data_temp, crs = open_raster(data_bucket, input_files[0], variable)
    data_nan = data_temp.where(data_temp != -9999000)
    data = data_nan / 1000

    local_raster = create_raster(data, crs)
    uploaded_raster = upload_raster(reference_time, local_raster, product_name, product_name)

    return [uploaded_raster]