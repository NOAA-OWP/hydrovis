
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

        local_raster = create_raster(data, crs, f"ana_past_{change[hour]}hr_snow_water_equivalent_change")

        uploaded_raster = upload_raster(local_raster, output_bucket, output_workspace)
        all_uploaded_rasters.append(uploaded_raster)

    return all_uploaded_rasters

import sys
sys.path.append("../utils")
from lambda_function import create_raster, upload_raster, open_raster

def main(product_name, data_bucket, input_files, reference_time, output_bucket, output_workspace):
    reversed_input_files = sorted(input_files, reverse=True)
    
    print(reversed_input_files)

    ### 10-DAY SNOW WATER EQUIVALENT CHANGE
    all_uploaded_rasters = []

    variable = "SNEQV"
    days = [1, 2, 3]  # defining loop for input files
    change = {1:3,2:5,3:10}  # defining dictionary for naming purposes
    
    print('Opening latest NWM output...')
    swe_present, crs = open_raster(data_bucket, reversed_input_files[0], variable)
    swe_present = swe_present.sel(time = swe_present.time[0])
    for day in days:

        swe_past, crs = open_raster(data_bucket, reversed_input_files[day], variable)
        # get the land files from past 10 days in reverse order
        swe_past = swe_past.sel(time = swe_past.time[0])
        swe_present_nan = swe_present.where(swe_present != -99990)
        swe_present_nan = swe_present_nan / 254 # convert kg/m2 to inches, should be 25.4 
        # but there's an extra order of mag
        swe_past_nan = swe_past.where(swe_past != -99990)
        swe_past_nan = swe_past_nan /254 #convert kg/m2 to inches

        swe_difference = swe_present_nan - swe_past_nan
        data = swe_difference.round(2)

        print("Creating raster...")
        local_raster = create_raster(data, crs, f"mrf_gfs_{change[day]}day_snow_water_equivalent_change")

        print(f"Uploading raster to {output_bucket}/{output_workspace}...")
        uploaded_raster = upload_raster(local_raster, output_bucket, output_workspace)
        all_uploaded_rasters.append(uploaded_raster)

    return all_uploaded_rasters
