variable "environment" {
  description = "Hydrovis environment"
  type        = string
}

variable "viz_environment" {
  description = "Visualization environment for code that should be used."
  type        = string
}

variable "viz_authoritative_bucket" {
  description = "S3 bucket where the viz authoritative data will live."
  type        = string
}

variable "nwm_data_bucket" {
  description = "S3 bucket where the NWM forecast data will live."
  type        = string
}

variable "fim_data_bucket" {
  description = "S3 bucket where the FIM data will live."
  type        = string
}

variable "fim_output_bucket" {
  description = "S3 bucket where the FIM outputs will live."
  type        = string
}

variable "lambda_data_bucket" {
  description = "S3 buckets where the lambda zip files will live."
  type        = string
}

variable "max_flows_bucket" {
  description = "S3 bucket where the outputted max flows will live."
  type        = string
}

variable "fim_version" {
  description = "FIM version to run"
  type        = string
}

variable "lambda_role" {
  type = string
}

variable "sns_topics" {
  description = "SnS topics"
  type        = map(any)
}

variable "es_logging_layer" {
  type = string
}

variable "xarray_layer" {
  type = string
}

variable "multiprocessing_layer" {
  type = string
}

variable "pandas_layer" {
  type = string
}

variable "rasterio_layer" {
  type = string
}

variable "mrf_rasterio_layer" {
  type = string
}

variable "viz_lambda_shared_funcs_layer" {
  type = string
}

data "aws_caller_identity" "current" {}

locals {
  max_flows_subscriptions = toset([
    "nwm_ingest_ana",
    "nwm_ingest_srf",
    "nwm_ingest_srf_hi",
    "nwm_ingest_srf_prvi",
    "nwm_ingest_mrf_3day",
    "nwm_ingest_mrf_5day",
    "nwm_ingest_mrf_10day"
  ])

  inundation_parent_subscriptions = toset([
    "nwm_ingest_ana",
    "nwm_ingest_ana_hi",
    "nwm_ingest_ana_prvi",
    "rnr_max_flows",
    "nwm_max_flows"
  ])
}

########################
## Max Flows Function ##
########################

resource "aws_lambda_function" "viz_max_flows" {
  function_name = "viz_max_flows_${var.environment}"
  description   = "Lambda function to create max streamflow files for NWM data"
  memory_size   = 512
  timeout       = 900

  environment {
    variables = {
      CACHE_DAYS       = 1
      MAX_FLOWS_BUCKET = var.max_flows_bucket
    }
  }

  s3_bucket = var.lambda_data_bucket
  s3_key    = "viz/lambda_functions/viz_max_flows.zip"

  runtime = "python3.7"
  handler = "lambda_function.lambda_handler"

  role = var.lambda_role

  layers = [
    var.xarray_layer,
    var.es_logging_layer,
    var.viz_lambda_shared_funcs_layer
  ]

  tags = {
    "Name" = "viz_max_flows_${var.environment}"
  }
}

resource "aws_sns_topic_subscription" "max_flows_subscriptions" {
  for_each  = local.max_flows_subscriptions
  topic_arn = var.sns_topics["${each.value}"].arn
  protocol  = "lambda"
  endpoint  = resource.aws_lambda_function.viz_max_flows.arn
}

resource "aws_lambda_permission" "max_flows_permissions" {
  for_each      = local.max_flows_subscriptions
  action        = "lambda:InvokeFunction"
  function_name = resource.aws_lambda_function.viz_max_flows.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.sns_topics["${each.value}"].arn
}

################################
## Inundation Parent Function ##
################################

resource "aws_lambda_function" "viz_inundation_parent" {
  function_name = "viz_inundation_parent_${var.environment}"
  description   = "Lambda function to process NWM data and kick off HUC inundation lambdas for each HUC with streams above bankfull threshold"
  memory_size   = 1024
  timeout       = 900

  environment {
    variables = {
      EMPTY_RASTER_BUCKET         = var.fim_data_bucket
      EMPTY_RASTER_MRF_PREFIX     = "empty_rasters/mrf"
      FIM_DATA_BUCKET             = var.fim_data_bucket
      VIZ_AUTHORITATIVE_BUCKET    = var.viz_authoritative_bucket
      NWM_DATA_BUCKET             = var.nwm_data_bucket
      PROCESSED_OUTPUT_BUCKET     = var.fim_output_bucket
      PROCESSED_OUTPUT_PREFIX     = "processing_outputs"
      RECURRENCE_FILENAME         = "viz/authoritative_data/derived_data/nwm_v21_recurrence_flows/nwm_v21_17c_bankfull_flows_w_huc6.nc"
      RECURRENCE_HAWAII_FILENAME  = "viz/authoritative_data/derived_data/nwm_v21_recurrence_flows/nwm_v20_recurrence_flows_hawaii.nc"
      RECURRENCE_PRVI_FILENAME    = "viz/authoritative_data/derived_data/nwm_v21_recurrence_flows/nwm_v21_recurrence_flows_prvi.nc"
      FIM_VERSION                 = var.fim_version
      max_flows_function          = resource.aws_lambda_function.viz_max_flows.arn
      viz_huc_inundation_function = resource.aws_lambda_function.viz_huc_inundation_processing.arn
    }
  }

  s3_bucket = var.lambda_data_bucket
  s3_key    = "viz/lambda_functions/viz_inundation_parent.zip"

  runtime = "python3.7"
  handler = "lambda_function.lambda_handler"

  role = var.lambda_role

  layers = [
    var.multiprocessing_layer,
    var.xarray_layer,
    var.es_logging_layer,
    var.viz_lambda_shared_funcs_layer
  ]

  tags = {
    "Name" = "viz_inundation_parent_${var.environment}"
  }
}

resource "aws_sns_topic_subscription" "inundation_parent_subscriptions" {
  for_each  = local.inundation_parent_subscriptions
  topic_arn = var.sns_topics["${each.value}"].arn
  protocol  = "lambda"
  endpoint  = resource.aws_lambda_function.viz_inundation_parent.arn
}

resource "aws_lambda_permission" "inundation_parent_permissions" {
  for_each      = local.inundation_parent_subscriptions
  action        = "lambda:InvokeFunction"
  function_name = resource.aws_lambda_function.viz_inundation_parent.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.sns_topics["${each.value}"].arn
}

########################################
## HUC Inundation Processing Function ##
########################################

resource "aws_lambda_function" "viz_huc_inundation_processing" {
  function_name = "viz_huc_inundation_processing_${var.environment}"
  description   = "Lambda function to calcuate FIM depths for each HUC"
  memory_size   = 3072
  timeout       = 900

  environment {
    variables = {
      EMPTY_RASTER_BUCKET          = var.fim_data_bucket
      EMPTY_RASTER_MRF_PREFIX      = "empty_rasters/mrf"
      FR_FIM_BUCKET                = var.fim_data_bucket
      FR_FIM_PREFIX                = "fim_${replace(var.fim_version, ".", "_")}_fr_c"
      MS_FIM_BUCKET                = var.fim_data_bucket
      MS_FIM_PREFIX                = "fim_${replace(var.fim_version, ".", "_")}_ms_c"
      PROCESSED_OUTPUT_BUCKET      = var.fim_output_bucket
      PROCESSED_OUTPUT_PREFIX      = "processing_outputs"
      viz_optimize_raster_function = resource.aws_lambda_function.viz_optimize_rasters.arn
    }
  }

  s3_bucket = var.lambda_data_bucket
  s3_key    = "viz/lambda_functions/viz_huc_inundation_processing.zip"

  runtime = "python3.6"
  handler = "lambda_function.lambda_handler"

  role = var.lambda_role

  layers = [
    var.rasterio_layer,
    var.pandas_layer,
    var.es_logging_layer,
    var.viz_lambda_shared_funcs_layer
  ]

  tags = {
    "Name" = "viz_huc_inundation_processing_${var.environment}"
  }
}

###############################
## Optimize Rasters Function ##
###############################

resource "aws_lambda_function" "viz_optimize_rasters" {
  function_name = "viz_optimize_rasters_${var.environment}"
  description   = "Lambda function to optimize tifs to mrfs"
  memory_size   = 1024
  timeout       = 900

  s3_bucket = var.lambda_data_bucket
  s3_key    = "viz/lambda_functions/viz_optimize_rasters.zip"

  runtime = "python3.6"
  handler = "lambda_function.lambda_handler"

  role = var.lambda_role

  layers = [
    var.mrf_rasterio_layer,
    var.es_logging_layer,
    var.viz_lambda_shared_funcs_layer
  ]

  tags = {
    "Name" = "viz_optimize_rasters_${var.environment}"
  }
}

output "max_flows" {
  value = aws_lambda_function.viz_max_flows
}

output "inundation_parent" {
  value = aws_lambda_function.viz_inundation_parent
}

output "huc_processing" {
  value = aws_lambda_function.viz_huc_inundation_processing
}

output "optimize_rasters" {
  value = aws_lambda_function.viz_optimize_rasters
}
