import os

ENVIRONMENT = os.environ.get('VIZ_ENVIRONMENT')
EGIS_HOST = os.environ.get('EGIS_HOST')
EGIS_USERNAME = os.environ.get('EGIS_USERNAME')
EGIS_PASSWORD = os.environ.get('EGIS_PASSWORD')
PORTAL = 'portal'
EGIS_DB_SCHEMA = "services"

CACHE_ROOT = os.environ.get('CACHE_ROOT')
FLAGS_ROOT = os.environ.get('FLAGS_ROOT')
PRO_PROJECT_ROOT = os.environ.get('PRO_PROJECT_ROOT')
PRISTINE_ROOT = os.environ.get('PRISTINE_ROOT')
PUBLISHED_ROOT = os.environ.get('PUBLISHED_ROOT')
WORKSPACE_ROOT = os.environ.get('WORKSPACE_ROOT')

PRIMARY_SERVER = os.environ.get('PRIMARY_SERVER')
IMAGE_SERVER = os.environ.get('IMAGE_SERVER')

OWP_FOLDER = 'owp'
NWM_FOLDER = 'nwm'
RFC_FOLDER = 'rfc'
REFERENCE_FOLDER = 'reference'
REFERRENCED_MOSAIC_FOLDER_NAME = 'reference_mosaic_data'

VALID_TIME = 'Valid Time'
REFERENCE_TIME = 'Reference Time'
SERVICES = 'services'

SCIENCE = 'science'
DEVELOPMENT = 'dev'
TESTING = 'ti'
STAGING = 'uat'
PRODUCTION = 'prod'

_SERVICE_NAME_TAG_MAP = {
    None: '_dev',
    '': '_dev',
    SCIENCE: '_dev',
    DEVELOPMENT: '_gamma',
    TESTING: '_alpha',
    STAGING: '_beta',
    PRODUCTION: ''
}

_SUMMARY_TAG_MAP = {
    None: ' (Dev)',
    '': ' (Dev)',
    SCIENCE: ' (Dev)',
    DEVELOPMENT: ' (Gamma)',
    TESTING: ' (Alpha)',
    STAGING: ' (Beta)',
    PRODUCTION: ''
}

SERVICE_NAME_TAG = _SERVICE_NAME_TAG_MAP[ENVIRONMENT]
SUMMARY_TAG = _SUMMARY_TAG_MAP[ENVIRONMENT]
