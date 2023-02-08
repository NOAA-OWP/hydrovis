import os
import arcpy

from aws_loosa.ec2.consts.paths import HYDROVIS_S3_CONNECTION_FILE_PATH, PROCESSED_OUTPUT_BUCKET, PROCESSED_OUTPUT_PREFIX


ACS_FILES = {
    "s3": {"connection_file": HYDROVIS_S3_CONNECTION_FILE_PATH, "s3_folder": PROCESSED_OUTPUT_PREFIX},
}

for configuration, metadata in ACS_FILES.items():
    acs_file = metadata['connection_file']
    s3_folder = metadata['s3_folder']

    if not os.path.exists(os.path.dirname(acs_file)):
        os.makedirs(os.path.dirname(acs_file))

    if not os.path.exists(acs_file):
        print(f"Creating ACS connection file for {acs_file} for {PROCESSED_OUTPUT_BUCKET}:{s3_folder}")
        arcpy.management.CreateCloudStorageConnectionFile(
            os.path.dirname(acs_file), os.path.basename(acs_file), "AMAZON", PROCESSED_OUTPUT_BUCKET, folder=s3_folder
        )
