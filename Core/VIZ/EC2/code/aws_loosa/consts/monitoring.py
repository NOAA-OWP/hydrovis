import os
from aws_loosa.processing_pipeline.utils.monitoring_consts import (DATE_FORMAT, EXECUTE_CALLED_TEXT, EXECUTING_PROCESSING_TEXT,
                                                         EXECUTE_SUCCESS_TEXT)

DATE_FORMAT = DATE_FORMAT
EXECUTE_CALLED_TEXT = EXECUTE_CALLED_TEXT
EXECUTING_PROCESSING_TEXT = EXECUTING_PROCESSING_TEXT
EXECUTE_SUCCESS_TEXT = EXECUTE_SUCCESS_TEXT

LOGSTASH_SOCKET = os.environ.get('LOGSTASH_SOCKET')
# PROCESS LOGGING
VALIDATING_WORKSPACE_TEXT = 'Validating workspace for %s...'
UPDATING_DATA_TEXT = 'Updating data for %s...'
UPDATING_PORTAL_ITEM_TEXT = 'Updating portal item for %s...'
PUBLISHING_SERVICE_TEXT = 'Publishing Server for %s...'
UPDATING_SERVICE_PROPS_TEXT = 'Updating service properties for %s...'

TRIGGER_RECOVERY_TEXT = 'Triggering "ArcGIS Server" service recovery system.'

RESOURCE_USAGE_TEXT = '%s Viz Service %s Usage - %s %s'
