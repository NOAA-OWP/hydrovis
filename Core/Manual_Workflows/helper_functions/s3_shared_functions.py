
# This script will eventually cover all types of communication with S3
# from get lists, uploading, downloading, moving, etc.
import io
import os

import boto3
import pandas as pd


# =======================================================
# *****************************
# CAUTION:  TODO: Aug 2024: This needs to be re-thought. I can easily overpower the notebook server depending on teh size of the notebooks
# *****************************

# Sep 2024: Deprecate: this is likely no longer used
# def download_S3_csv_files_to_df(bucket_name, s3_src_folder_prefix, is_verbose=False):
    
#     '''
#     Overview: All files are downloaded and put into a dataframe raw
    
#     returns:
#         a dataframe
#     '''

#     s3_client = boto3.client("s3")

#     default_kwargs = {"Bucket": bucket_name, "Prefix": s3_src_folder_prefix}

#     next_token = ""
    
#     rtn_df = None
#     ctr = 0

#     print(f"Downloading data from s3://{bucket_name}/{s3_src_folder_prefix}")
#     print("")
    
#     while next_token is not None:
#         updated_kwargs = default_kwargs.copy()
#         if next_token != "":
#             updated_kwargs["ContinuationToken"] = next_token

#         # will limit to 1000 objects - hence tokens
#         response = s3_client.list_objects_v2(**updated_kwargs)
#         if response.get("KeyCount") == 0:
#             # some recs may have been added in earlier pages
#             next_token = response.get("NextContinuationToken")
#             continue        
            
#         contents = response.get("Contents")
#         if contents is None:
#             raise Exception("s3 contents not did not load correctly")

#         for result in contents:
#             key = result.get("Key")
#             if key[-1] != "/": # if it was a folder (ending in a slash, we skip it)
#                 # download and load the contents into the table
#                 full_file_url = f"s3://{bucket_name}/{key}"
                
#                 if not full_file_url.endswith(".csv"):
#                     print(f"... Found file that is not a csv and was skipped : {full_file_url}")
#                     continue
                
#                 if is_verbose:
#                     print(f"... Downloading: {key}")
            
#                 #s3_resp = s3.get_object(Bucket=bucket_name, Key=key)
#                 #csv_content = response['Body'].read().decode('utf-8')
            
#                 # then we let the first rec set the headers
#                 # pandas can load directly from S3
#                 if rtn_df is None:
#                     # all fields will be loaded as string and future code can change as needed.
#                     # padnas read_csv is having trouble with data type for columns, so let's do it manually
#                     rtn_df = pd.read_csv(full_file_url)
#                     #rtn_df = pd.read_csv(io.StringIO(csv_content))
#                     continue
                
#                 #file_df = pd.read_csv(io.StringIO(csv_content))
#                 file_df = pd.read_csv(full_file_url)                
#                 rtn_df = pd.concat([rtn_df, file_df])
#                 ctr = ctr + 1
                
#                 # TODO: Takes out this test
#                 break # just to see how it looks and load
                
                    
#         next_token = response.get("NextContinuationToken")
#         break

#     # end of while
    
#     rtn_df = rtn_df.fillna(0)
#     print(f"Downloaded {ctr} files from s3://{bucket_name}/{s3_src_folder_prefix}")
#     return rtn_df



# =======================================================
# *****************************
# CAUTION:  TODO: Aug 2024: This needs to be re-thought. I can easily overpower the notebook server depending on teh size of the notebooks
# *****************************
def load_S3_csv_to_df(s3_file_path, is_verbose=False):
    '''
    Overview:
        - a full s3 file path 
          ie) s3://hydrovis-ti-deployment-us-east-1/fim/hand_4_5_11_1/qa_datasets/fim_performance_catchments.csv
    Returns:
        - A dataframe with the csv data loaded
    '''

    if s3_file_path is None or s3_file_path == '' or len(s3_file_path) < 5:
        raise Exception("s3_file_path is invalid - not set, empty or too short")

    if s3_file.endswith(".csv") is False:
        raise Exception(f"File name is not valid (not a csv): {s3_file}")

    s3_client = boto3.client('s3')

    if s3_file.endswith(".csv") is False:
        raise Exception(f"File name is not valid (not a csv): {s3_file}")

    # Manage the direction of the slashes just cases
    s3_file = s3_file.replace("\\", "/")

    if s3_file.startswith("/"): # remove it
        s3_file = s3_file.lstrip("/")

    full_file_url = f"s3://{bucket_name}/{s3_file}"
    if is_verbose:
        print(f".. Downloading: {full_file_url}")

    rtn_df = pd.read_csv(full_file_url)

    print(f"... {len(list_file_paths)} files downloaded and loaded into the dataframe")
        
    return rtn_df


# =======================================================
def get_s3_subfolder_file_names(bucket_name, s3_src_folder_prefix, is_verbose=False):
    
    '''
    Overview: Gets a list of file (not folders in a s3 folder (well.. prefix)
    
    returns:
        a list of file names and path (keys), fully qualified including the bucket and src_folder_path
    '''

    s3_client = boto3.client("s3")

    default_kwargs = {"Bucket": bucket_name, "Prefix": s3_src_folder_prefix}

    next_token = ""
    
    file_list = []

    print(f"Getting file list from s3://{bucket_name}/{s3_src_folder_prefix}")
    print("")
    
    while next_token is not None:
        updated_kwargs = default_kwargs.copy()
        if next_token != "":
            updated_kwargs["ContinuationToken"] = next_token

        # will limit to 1000 objects - hence tokens, even for list_objects_v2
        response = s3_client.list_objects_v2(**updated_kwargs)
        if response.get("KeyCount") == 0:
            # some recs may have been added in earlier pages
            next_token = response.get("NextContinuationToken")
            continue        
            
        contents = response.get("Contents")
        if contents is None:
            raise Exception("s3 contents not did not load correctly")

        for result in contents:
            key = result.get("Key")
            if key[-1] != "/": # if it was a folder (ending in a slash, we skip it)
                # download and load the contents into the table
                full_file_url = f"s3://{bucket_name}/{key}"
                
                if is_verbose:
                    print(f"... Found file name: {key}")
            
                file_list.append(full_file_url)
                    
        next_token = response.get("NextContinuationToken")

    # end of while
    
    print(f"Found {len(file_list)} file names from s3://{bucket_name}/{s3_src_folder_prefix}")
    return file_list

