import os
import re
import boto3

s3_client = boto3.client('s3')

def upload_rnr_max_flows(bucket, s3_prefix, folder_path): 
    for filename in os.listdir(folder_path):
        if filename.endswith('.csv') and "max_flows" in filename:
            matches = re.findall(r"(\d{4})(\d{2})(\d{2})(\d{4})", filename)[0]
            year = matches[0]
            month = matches[1]
            day = matches[2]
            hour = matches[3]
            local_path = os.path.join(folder_path, filename)
            s3_key = f"{s3_prefix}{year}{month}{day}/rnr_{hour[:2]}_max_flows.csv"
            s3_client.upload_file(local_path, bucket, s3_key)
            print(f"Uploaded {local_path} to {bucket}/{s3_key}")

########################################################################################################################################
if __name__ == '__main__':
    bucket = 'hydrovis-ti-rnr-us-east-1'
    s3_prefix = 'max_flows/replace_route/'
    folder_of_rnr_max_flows_exports = r"C:\Users\Administrator\Desktop\rnr_outputs"
    upload_rnr_max_flows(bucket, s3_prefix, folder_of_rnr_max_flows_exports)


    