import sys
sys.path.append("../utils")
from lambda_function import open_raster, create_raster, upload_raster

def main(product_name, data_bucket, input_files, reference_time):
    reversed_input_files = sorted(input_files, reverse=True)

    ### 72-HOUR SNOW WATER EQUIVALENT CHANGE
    all_uploaded_rasters = []

    variable = "SNEQV" 
    hours = [1, 2, 3] #defining loop for input files
    change = {1:24,2:48,3:72} #defining dictionary for naming purposes
    for hour in hours:
        swe_present, crs = open_raster(data_bucket, reversed_input_files[0], variable)
        swe_past, crs = open_raster(data_bucket, reversed_input_files[hour], variable)
        #get the land files from past 3 days (72hours) in reverse order

        swe_present = swe_present.sel(time = swe_present.time[0])
        swe_past = swe_past.sel(time = swe_past.time[0])

        swe_present_nan = swe_present.where(swe_present != -99990)
        swe_present_nan = swe_present_nan / 254 # convert kg/m2 to inches, should be 25.4 
        #but there's an extra order of mag
        swe_past_nan = swe_past.where(swe_past != -99990)
        swe_past_nan = swe_past_nan /254 #convert kg/m2 to inches

        swe_difference = swe_present_nan - swe_past_nan
        data = swe_difference.round(2)

        local_raster = create_raster(data, crs)
        raster_name = f"ana_{change[hour]}hr_snow_water_equiv_change" 
        uploaded_raster = upload_raster(reference_time, local_raster, product_name, raster_name)
        all_uploaded_rasters.append(uploaded_raster)

    return all_uploaded_rasters
