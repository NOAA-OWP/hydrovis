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
def download_files_from_s3(bucket_name, folder_name, destination_dir, sso_profile, include_files_with=None, skip_files_with=None, overwrite = False, output_format = 'gpkg'):
    if os.path.exists(destination_dir) is False:
        pathlib.Path(destination_dir).mkdir(parents=True, exist_ok=True)
    
    if sso_profile:
        s3_session = boto3.Session(profile_name=sso_profile)
        s3_client = s3_session.client('s3')
    else:
        s3_client = boto3.client('s3')

    # Retrieve list of objects in the specified folder
    paginator = s3_client.get_paginator('list_objects_v2')
    pages = paginator.paginate(Bucket=bucket_name, Prefix=folder_name)

    files_found = False
    for page in pages:
        # Iterate over each object and download it
        try:
            for obj in page['Contents']:
                # Extract the file name from the object key
                file_name = os.path.basename(obj['Key'])

                # Construct the local file path
                local_file_path = os.path.join(destination_dir, file_name)
                final_file_path = local_file_path.replace(".csv", f".{output_format}").replace("_publish_", "_")

                if any([x in file_name for x in skip_files_with]):
                    continue
                elif len(include_files_with) > 0 and any([x not in file_name for x in include_files_with]):
                    continue
                else:
                    files_found = True
                    if overwrite is False and (os.path.exists(local_file_path) or os.path.exists(final_file_path)):
                        print(f"{local_file_path} csv or {output_format} already exists and overwrite is false. Skipping.")
                    else:
                        print(f"Match found. Downloading: {file_name}...", end="", flush=True)
                        s3_client.download_file(bucket_name, obj['Key'], local_file_path)
                        print("... Done.")
        except Exception as err:
            print(f"there was error: {err=}, {type(err)=}")
    if not files_found:
        print('No objects found on S3 matching the given criteria.')

# Function to convert CSV to Geospatial file format
def convert_csv_to_geospatial(csv_file, parts=1, output_format = 'gpkg', clip_to_states=None, delete_csv=True):
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
            print(f"... Filtering to {clip_to_states}...")
            df_all = df_all[df_all["state"].isin(clip_to_states)]
        else:
            print(f"State column not found in {csv_file}. Run for nationwide by not providing states for clipping.")
            return

    print("... Converting to geodataframe...")
    df_all.drop(df_all[df_all['geom'].isna()].index, inplace=True) #Remove any null geoms
    gdf = gpd.GeoDataFrame(df_all, geometry=df_all['geom'].apply(wkt.loads), crs='EPSG:3857')
    gdf = gdf.drop(columns=['geom'])
    output_filename = csv_file.replace(".csv",f".{output_format}").replace("_publish_", "_") # change file extension and remove publish schema reference from filename.

    # Save to output file
    print(f"... Saving output {output_format} file...")
    if output_format == 'gpkg':
        driver = 'GPKG'
    else:
        driver = 'ESRI Shapefile'
    gdf.to_file(output_filename, driver=driver)

    # Delete the csvs if arg is true
    if delete_csv is True:
        print(f"... Deleting CSV files...")
        for file in csv_files:
            os.remove(file)
    
    print(f"... Done ({round(time.time()-convert_start,0)/60} minutes)")

# Function to iterate through folder and convert CSVs to geospatial files
def convert_folder_csvs_to_geospatial(folder_path, output_format='gpkg', clip_to_states=None, overwrite=False, delete_csv=True):
    # Iterate through files in the folder
    for filename in os.listdir(folder_path):
        if filename.endswith('.csv') and "ana_streamflow" not in filename:
            csv_file_path = os.path.join(folder_path, filename)
            out_filepath = csv_file_path.replace(".csv", f".{output_format}").replace("_publish_", "_")
            if os.path.exists(out_filepath) and overwrite is False:
                print(f"{out_filepath} already exists and overwrite is false. Skipping.")
            else:         
                # Check to see if mulitple parts of the csv file exist (postgresql breaks large datasets up into csv_partx subsequent files)
                parts=1
                for x in range(2,5):
                    if os.path.exists(csv_file_path + f"_part{x}"):
                        parts+=1
                # Convert the csv files to geospatial formats
                convert_csv_to_geospatial(csv_file_path, parts=parts, output_format=output_format, clip_to_states=clip_to_states, delete_csv=delete_csv)

########################################################################################################################################
if __name__ == '__main__':
    start = time.time()
    
    # This script will use the input args below to search AWS S3 for viz cache data, download matching files, filter to state(s) if desired, and export to a geospatial format (gpkg, shp, etc.).
    # This script is not schema dependent, so it should work most of the time for any dates after February 2023, when we started saving cache files as csv
    # (although state clipping will only work when the csv output files have a state column - which has still only been implemented in UAT as of 6/6/2023)

    # I'd suggest cloning the ArcGIS python environment into a custom env to run this (follow steps 1-5 of the old viz setup wiki at https://vlab.noaa.gov/redmine/projects/owp_gid-data-visualization/wiki/Set_Up)
    # You'll also need to install geopandas with `pip install geopandas`
    # Before you run this script, use `aws sso login --profile <profile name>` to authenticate with AWS, and use that profile name in the arg below. If you need help setting
    # this up, see the Configuring AWS CLI section of the Hydrovis viz Guide at https://docs.google.com/document/d/1UIbAQycG-mWw5XwDPDunkQED5O96YtsbrOA4MMZ9zmA/edit?usp=sharing 
    
    ########## Specify your Args Here #############
    sso_profile = "prod-ro" # The name of the AWS SSO profile you created, or set to None if you want to pull from the current environment of an EC2 machine (see notes above)
    bucket_name = 'hydrovis-prod-fim-us-east-1' # Set this based on the hydrovis environment you are pulling from, e.g. 'hydrovis-ti-fim-us-east-1', 'hydrovis-uat-fim-us-east-1', 'hydrovis-prod-fim-us-east-1'
    
    include_files_with = [] # Anything you want to be included when filtering S3 files e.g ["ana", "mrf"] or ["mrf_"]
    skip_files_with = [] # Anything you want to be skipped when filtering S3 files e.g. ["ana_streamflow", "rapid_onset_flooding"]
    clip_to_states = ["WA"] # Provide a list of state abbreviations to clip to set states, e.g. ["AL", "GA", "MS"]
    output_format = "gpkg" # Set to gpkg or shp - Can add any OGR formats, with some tweaks to the file_format logic in the functions above. BEWARE - large FIM files can be too large for shapefiles, and results may be truncated.
    output_dir = r"/home/user/documents/output/" # Directory where you want output files saved.
    overwrite = False # This will automatically skip files that have already been downloaded and/or converted when running the script when set to False (default).
    delete_csv = True # This will delete the csv files after conversion
    ###############################################
    events = [
        {"start_date": date(2023, 5, 20), "end_date": date(2023, 5, 20), "reference_times": ["1200"]}
    ]

    ###############################################
    for event in events:
        start_date = event['start_date']
        end_date = event['end_date']
        reference_times = event['reference_times']
        # Loop through days/hours specified
        for day in daterange(start_date, end_date):
            ref_date = day.strftime("%Y%m%d")
            for reference_time in reference_times:
                folder_name = f"viz_cache/{ref_date}/{reference_time}/"
                destination_dir = fr"{output_dir}/{ref_date}/{reference_time}"
                # Download files from S3
                print(f"Searching Viz Cache for /{ref_date}/{reference_time}/ with files including {include_files_with} and not including {skip_files_with}.")
                download_files_from_s3(bucket_name, folder_name, destination_dir, sso_profile, include_files_with=include_files_with, skip_files_with=skip_files_with, overwrite=False, output_format=output_format)
                # Convert to geospatial (clip to states as well, if desired)
                convert_folder_csvs_to_geospatial(destination_dir, output_format=output_format, clip_to_states=clip_to_states, delete_csv=delete_csv)
    
    print(f"Finished in {round(time.time()-start,0)/60} minutes")
