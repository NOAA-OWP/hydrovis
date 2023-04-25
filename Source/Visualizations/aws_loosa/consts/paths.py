import os
import aws_loosa

AUTHORITATIVE_ROOT = os.environ.get('AUTHORITATIVE_ROOT')
PUBLISHED_ROOT = os.environ.get('PUBLISHED_ROOT')
FIM_DATA_BUCKET = os.environ.get('FIM_DATA_BUCKET')
FIM_OUTPUT_BUCKET = os.environ.get('FIM_OUTPUT_BUCKET')
RNR_MAX_FLOWS_DATA_BUCKET = os.environ.get('RNR_MAX_FLOWS_DATA_BUCKET')
NWM_MAX_VALUES_DATA_BUCKET = os.environ.get('NWM_MAX_VALUES_DATA_BUCKET')

# REPOSITORY PATHS
AWS_LOOSA_DIR = os.path.dirname(aws_loosa.__file__)
PIPELINES_DIR = os.path.join(AWS_LOOSA_DIR, 'pipelines')
VISUALIZATIONS_DIR = os.path.dirname(AWS_LOOSA_DIR)
CODE_SOURCE_DIR = os.path.dirname(VISUALIZATIONS_DIR)
HYDROVIS_DIR = os.path.dirname(CODE_SOURCE_DIR)
MAPX_DIR = os.path.join(HYDROVIS_DIR, 'Core', 'LAMBDA', 'viz_functions', 'viz_publish_service', 'services')
EMPTY_PRO_PROJECT_DIR = os.path.join(AWS_LOOSA_DIR, 'utils')

# Connection Files
CONNECTION_FILES_DIR = f"{PUBLISHED_ROOT}\\connection_files"
HYDROVIS_S3_CONNECTION_FILE_PATH = f"{CONNECTION_FILES_DIR}\\HydroVis_S3_processing_outputs.acs"

HYDROVIS_EGIS_DB_SDE = f"{CONNECTION_FILES_DIR}\\egis_db.sde"

# MD Files
MD_PUBLISH_JSON = f"{AUTHORITATIVE_ROOT}\\mosaic_dataset_configs\\md_image_service.json"

HYDROVIS_CACHE_ROOT = f"{PUBLISHED_ROOT}\\vizimgcache"
INUNDATION_SYMBOLOGY = f"{AUTHORITATIVE_ROOT}\\mosaic_dataset_configs\\symbology\\Inundation_Extent_Symbology.rft.xml"

# S3 Paths
PROCESSED_OUTPUT_BUCKET = FIM_OUTPUT_BUCKET
PROCESSED_OUTPUT_PREFIX = "processing_outputs"
EMPTY_RASTER_PREFIX = 'empty_rasters/mrf'
RNR_MAX_FLOWS_DATA_BUCKET = RNR_MAX_FLOWS_DATA_BUCKET
NWM_MAX_VALUES_DATA_BUCKET = NWM_MAX_VALUES_DATA_BUCKET
MAX_FLOWS_PREFIX = 'max_flows'
TRIGGER_FILES_PREFIX = 'processing_outputs'
FIM_DATA_BUCKET = FIM_DATA_BUCKET

PERCENTILE_TABLE_2ND = f"{AUTHORITATIVE_ROOT}\\derived_data\\nwm_v21_7_day_average_percentiles\\final_7day_all_2th_perc.nc"  # noqa: E501
PERCENTILE_TABLE_5TH = f"{AUTHORITATIVE_ROOT}\\derived_data\\nwm_v21_7_day_average_percentiles\\final_7day_all_5th_perc.nc"  # noqa: E501
PERCENTILE_TABLE_10TH = f"{AUTHORITATIVE_ROOT}\\derived_data\\nwm_v21_7_day_average_percentiles\\final_7day_all_10th_perc.nc"  # noqa: E501
PERCENTILE_TABLE_20TH = f"{AUTHORITATIVE_ROOT}\\derived_data\\nwm_v21_7_day_average_percentiles\\final_7day_all_20th_perc.nc"  # noqa: E501
PERCENTILE_TABLE_25TH = f"{AUTHORITATIVE_ROOT}\\derived_data\\nwm_v21_7_day_average_percentiles\\final_7day_all_25th_perc.nc"  # noqa: E501
PERCENTILE_TABLE_75TH = f"{AUTHORITATIVE_ROOT}\\derived_data\\nwm_v21_7_day_average_percentiles\\final_7day_all_75th_perc.nc"  # noqa: E501
PERCENTILE_TABLE_90TH = f"{AUTHORITATIVE_ROOT}\\derived_data\\nwm_v21_7_day_average_percentiles\\final_7day_all_90th_perc.nc"  # noqa: E501
PERCENTILE_TABLE_95TH = f"{AUTHORITATIVE_ROOT}\\derived_data\\nwm_v21_7_day_average_percentiles\\final_7day_all_95th_perc.nc"  # noqa: E501
PERCENTILE_14_TABLE_2ND = f"{AUTHORITATIVE_ROOT}\\derived_data\\nwm_v21_14_day_average_percentiles\\final_14day_all_2th_perc.nc"  # noqa: E501
PERCENTILE_14_TABLE_5TH = f"{AUTHORITATIVE_ROOT}\\derived_data\\nwm_v21_14_day_average_percentiles\\final_14day_all_5th_perc.nc"  # noqa: E501
PERCENTILE_14_TABLE_10TH = f"{AUTHORITATIVE_ROOT}\\derived_data\\nwm_v21_14_day_average_percentiles\\final_14day_all_10th_perc.nc"  # noqa: E501
PERCENTILE_14_TABLE_25TH = f"{AUTHORITATIVE_ROOT}\\derived_data\\nwm_v21_14_day_average_percentiles\\final_14day_all_25th_perc.nc"  # noqa: E501
PERCENTILE_14_TABLE_20TH = f"{AUTHORITATIVE_ROOT}\\derived_data\\nwm_v21_14_day_average_percentiles\\final_14day_all_20th_perc.nc"  # noqa: E501
PERCENTILE_14_TABLE_75TH = f"{AUTHORITATIVE_ROOT}\\derived_data\\nwm_v21_14_day_average_percentiles\\final_14day_all_75th_perc.nc"  # noqa: E501
PERCENTILE_14_TABLE_90TH = f"{AUTHORITATIVE_ROOT}\\derived_data\\nwm_v21_14_day_average_percentiles\\final_14day_all_90th_perc.nc"  # noqa: E501
PERCENTILE_14_TABLE_95TH = f"{AUTHORITATIVE_ROOT}\\derived_data\\nwm_v21_14_day_average_percentiles\\final_14day_all_95th_perc.nc"  # noqa: E501
