import os

TEMP = os.getenv("TEMP")
TOTAL_PROCESSES_ENV_VAR = 'TOTAL_PROCESSES'
PIPELINE_MACHINE_ENV_VAR = 'PIPELINE_MACHINE'

CFS_FROM_CMS = 35.315
FT_FROM_METERS = 3.281
METERS_TO_MILES = 0.000621371

INSUFFICIENT_DATA_ERROR_CODE = -9998

hydrovis_env_map = {
    "development": 'dev',
    "dev": 'dev',
    "testing": 'ti',
    "ti": 'ti',
    "staging": "uat",
    "uat": 'uat',
    "production": 'prod',
    "prod": 'prod'
}
