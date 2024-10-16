import boto3


# Function to download files from a folder in S3
def download_files_from_s3(src, dst, ignore_str):
    from_profile = src['profile']
    from_bucket = src['bucket']
    from_path = src['path']
    from_s3_session = boto3.Session(profile_name=from_profile)
    from_client = from_s3_session.client('s3')

    to_profile = dst['profile']
    to_bucket = dst['bucket']
    to_s3_session = boto3.Session(profile_name=to_profile)
    to_client = to_s3_session.client('s3')

    # Retrieve list of objects in the specified folder
    paginator = from_client.get_paginator('list_objects_v2')
    pages = paginator.paginate(Bucket=from_bucket, Prefix=from_path)

    for page in pages:
        # Iterate over each object and download it
        for obj in page['Contents']:
            key = obj['Key']
            if ignore_str and ignore_str in key:
                continue
            print(f'Writing {key} from {from_bucket} to {to_bucket}')
            obj = from_client.get_object(Bucket=from_bucket, Key=key)
            content = obj['Body'].read()
            to_client.put_object(Body=content, Bucket=to_bucket, Key=key)


if __name__ == '__main__':
    src = {
        'profile': 'ti',
        'bucket': 'hydrovis-ti-deployment-us-east-1',
        'path': 'viz_db_dumps/vizDB_derived_v2.1.7_dump.sql'
    }
    dst = {
        'profile': 'prod',
        'bucket': 'hydrovis-uat-deployment-us-east-1'
    }
    ignore_str = ''
    download_files_from_s3(src, dst, ignore_str)
