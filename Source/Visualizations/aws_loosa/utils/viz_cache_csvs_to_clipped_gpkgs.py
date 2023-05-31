import os
import pathlib
import boto3
import pandas as pd
import geopandas as gpd
from shapely import wkt
import time
from datetime import date, timedelta

# Function to get a daterange list from a start and end date.
def daterange(start_date, end_date):
    for n in range(int((end_date - start_date).days + 1)):
        yield start_date + timedelta(n)

# Function to download files from a folder in S3
def download_files_from_s3(bucket_name, folder_name, destination_dir, sso_profile, include_files_with=None, skip_files_with=None, overwrite = False):
    if os.path.exists(destination_dir) is False:
        pathlib.Path(destination_dir).mkdir(parents=True, exist_ok=True)
    
    if sso_profile:
        s3_session = boto3.Session(profile_name=sso_profile)
        s3_client = s3_session.client('s3')
    else:
        s3_client = boto3.client('s3')

    # Retrieve list of objects in the specified folder
    response = s3_client.list_objects_v2(Bucket=bucket_name, Prefix=folder_name)

    # If no objects, return
    if len(response['Contents']) == 0:
        print("No objects found on S3 matching given criteria.")
        return
    
    # Iterate over each object and download it
    for obj in response['Contents']:
        # Extract the file name from the object key
        file_name = os.path.basename(obj['Key'])

        # Construct the local file path
        local_file_path = os.path.join(destination_dir, file_name)
        gpkg_file_path = local_file_path.replace(".csv", ".gpkg")

        if any([x in file_name for x in skip_files_with]):
            continue
        elif len(include_files_with) > 0 and any([x not in file_name for x in include_files_with]):
            continue
        else:
            if overwrite is False and (os.path.exists(local_file_path) or os.path.exists(gpkg_file_path)):
                print(f"{local_file_path} csv or gpkg already exists and overwrite is false. Skipping.")
            else:
                s3_client.download_file(bucket_name, obj['Key'], local_file_path)
                print(f"Downloaded: {obj['Key']}")

# Function to convert CSV to GeoPackage
def convert_csv_to_geopackage(csv_file, parts=1, clip_to_states=None, delete_csv=True):
    convert_start = time.time()
    # create a list of csv files to convert / append when multiple parts
    csv_files = []
    csv_files.append(csv_file)
    for x in range(2, parts+1):
        csv_files.append(csv_file + f"_part{x}")
    
    # Get the headers from the first file
    with open(csv_file, 'r') as f:
        headers = f.readline().strip().split(',')
    
    # Convert each csv file in the list to a geodataframe
    dataframes = []
    for i, current_file in enumerate(csv_files):
        print(f"- Opening {current_file} - Part ({i+1} of {len(csv_files)})")
        df = pd.read_csv(current_file, names=headers, header=0)
        dataframes.append(df)
    df_all = pd.DataFrame(pd.concat(dataframes, ignore_index=True))
    
    # Clip to States (if applicable)
    if clip_to_states:
        if 'state' in df_all.columns:
            print(f"...Filtering to {clip_to_states}...")
            df_all = df_all[df_all["state"].isin(clip_to_states)]
        else:
            print(f"State column not found in {csv_file}. Run for nationwide by not providing states for clipping.")
            return

    print("...Converting to geodataframe...")
    gdf = gpd.GeoDataFrame(df_all, geometry=df['geom'].apply(wkt.loads), crs='EPSG:3857')
    gdf = gdf.drop(columns=['geom'])
    gpkg_filename = csv_file.replace(".csv",".gpkg")

    # Save to geopackage
    print(f"...Saving output gpkg file...")
    gdf.to_file(gpkg_filename, driver='GPKG')

    # Delete the csvs if arg is true
    if delete_csv is True:
        print(f"...Deleting CSV files...")
        for file in csv_files:
            os.remove(file)
    
    print(f"...Done... ({round(time.time()-convert_start,0)/60} minutes)")

# Function to iterate through folder and convert CSVs to GeoPackages
def convert_folder_csvs_to_geopackages(folder_path, clip_to_states=None, overwrite=False):
    # Iterate through files in the folder
    for filename in os.listdir(folder_path):
        if filename.endswith('.csv') and "ana_streamflow" not in filename:
            csv_file_path = os.path.join(folder_path, filename)
            gpkg_filepath = csv_file_path.replace(".csv", ".gpkg")
            if os.path.exists(gpkg_filepath) and overwrite is False:
                print(f"{gpkg_filepath} already exists and overwrite is false. Skipping.")
            else:         
                # Check to see if mulitple parts of the csv file exist (postgresql breaks large datasets up into csv_partx subsequent files)
                parts=1
                for x in range(2,5):
                    if os.path.exists(csv_file_path + f"_part{x}"):
                        parts+=1
                # Convert the csv files to geopackages
                convert_csv_to_geopackage(csv_file_path, parts=parts, clip_to_states=clip_to_states, delete_csv=True)

########################################################################################################################################
if __name__ == '__main__':
    start = time.time()
    
    ########## Specify your Args Here #############
    sso_profile = None
    bucket_name = 'hydrovis-ti-fim-us-east-1'
    start_date = date(2021, 10, 25)
    end_date = date(2021, 10, 28)
    reference_times = ["1200"]
    include_files_with = []
    skip_files_with = ["_part2", "_part3", "ana_streamflow"]
    clip_to_states = []
    ###############################################
    
    # Loop through days/hours specified
    for day in daterange(start_date, end_date):
        ref_date = day.strftime("%Y%m%d")
        for reference_time in reference_times:
            folder_name = f"viz_cache/{ref_date}/{reference_time}/"
            destination_dir = fr"C:\Users\Administrator\Desktop\VPP Data Requests\{ref_date}\{reference_time}"
            # Download files from S3
            print(f"Searching Viz Cache for /{ref_date}/{reference_time}/ with files including {include_files_with} and not including {skip_files_with}.")
            download_files_from_s3(bucket_name, folder_name, destination_dir, sso_profile, include_files_with=include_files_with, skip_files_with=skip_files_with, overwrite=False)
            # Convert to geopackages (clip to states as well, if desired)
            convert_folder_csvs_to_geopackages(destination_dir, clip_to_states=clip_to_states)
    
    print(f"Finished in {round(time.time()-start,0)/60} minutes")