set from_env=uat
set to_env=prod
set from_bucket=hydrovis-uat-deployment-us-east-1
set to_bucket=hydrovis-prod-deployment-us-east-1
set s3_path=viz/db_pipeline/db_dumps/
set temp_transfer_path=C:\temp\temp_db_dumps

:: Download
aws sso login --profile %from_env%
aws s3 sync s3://%from_bucket%/%s3_path% %temp_transfer_path% --profile %from_env%


:: Upload
aws sso login --profile %to_env%
aws s3 sync %temp_transfer_path% s3://%to_bucket%/%s3_path% --profile %to_env%


