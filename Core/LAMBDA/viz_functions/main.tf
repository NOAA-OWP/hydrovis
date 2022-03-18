variable "environment" {
  description = "Hydrovis environment"
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
  description = "Role to use for the lambda functions."
  type = string
}

variable "db_lambda_security_groups" {
  description = "Security group for db-pipeline lambdas."
  type = list(any)
}

variable "nat_sg_group" {
  type = string
}

variable "db_lambda_subnets"{
  description = "Subnets to use for the db-pipeline lambdas."
  type = list(any)
}

variable "sns_topics" {
  description = "SnS topics"
  type        = map(any)
}

variable "email_sns_topics" {
  description = "SnS topics"
  type        = map(any)
}

variable "viz_db_host" {
  description = "Hostname of the viz processing RDS instance."
  type        = string
}

variable "viz_db_name" {
  description = "DB Name of the viz processing RDS instance."
  type        = string
}

variable "egis_db_host" {
  description = "Hostname of the EGIS RDS instance."
  type        = string
}

variable "egis_db_name" {
  type = string
}

variable "viz_db_user_secret_string" {
  description = "The secret string of the viz_processing data base user to write/read data as."
  type        = string
}

variable "egis_db_secret_string" {
  description = "The secret string for the egis rds database."
  type        = string
}

variable "egis_portal_password" {
  description = "The password for the egis portal user to publish as."
  type        = string
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

variable "psycopg2_sqlalchemy_layer" {
  type = string
}

variable "arcgis_python_api_layer" {
  type = string
}

variable "viz_lambda_shared_funcs_layer" {
  type = string
}

variable "dataservices_ip" {
  type = string
}

data "aws_caller_identity" "current" {}

locals {
  egis_host              = var.environment == "prod" ? "https://maps.water.noaa.gov/portal" : var.environment == "uat" ? "https://maps-staging.water.noaa.gov/portal" : var.environment == "ti" ? "https://maps-testing.water.noaa.gov/portal" : "https://hydrovis-dev.nwc.nws.noaa.gov/portal"
  service_suffix         = var.environment == "prod" ? "" : var.environment == "uat" ? "_beta" : var.environment == "ti" ? "_alpha" : "_gamma"
  
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
  
  db_ingest_subscriptions = toset([
    "nwm_ingest_ana",
    "nwm_ingest_ana_hi",
    "nwm_ingest_ana_prvi",
    "nwm_ingest_srf",
    "nwm_ingest_srf_hi",
    "nwm_ingest_srf_prvi",
    "nwm_ingest_mrf_10day",
    "rnr_max_flows"
  ])
}

###############################
## WRDS API Handler Function ##
###############################
resource "aws_lambda_function" "viz_wrds_api_handler" {
  function_name = "viz_wrds_api_handler_${var.environment}"
  description   = "Lambda function to ping WRDS API and format outputs for processing."
  memory_size   = 512
  timeout       = 900
  vpc_config {
  	security_group_ids = [var.nat_sg_group]
  	subnet_ids = var.db_lambda_subnets
  }
  environment {
    variables = {
      DATASERVICES_HOST	= var.dataservices_ip
      PROCESSED_OUTPUT_BUCKET	= var.max_flows_bucket
      PROCESSED_OUTPUT_PREFIX	= "max_stage/ahps"
      DB_INGEST_FUNCTION = aws_lambda_function.viz_db_ingest.arn
    }
  }
  s3_bucket = var.lambda_data_bucket
  s3_key    = "viz/lambda_functions/viz_wrds_api_handler.zip"
  runtime = "python3.7"
  handler = "lambda_function.lambda_handler"
  role = var.lambda_role
  layers = [
    var.xarray_layer,
    var.es_logging_layer,
    var.viz_lambda_shared_funcs_layer
  ]
  tags = {
    "Name" = "viz_wrds_api_handler_${var.environment}"
  }
}

resource "aws_cloudwatch_event_rule" "every_fifteen_minutes" {
    name = "every_fifteen_minutes"
    description = "Fires every fifteen minutes"
    schedule_expression = "cron(0/15 * * * ? *)"
}

resource "aws_cloudwatch_event_target" "check_lambda_every_five_minutes" {
    rule = "${aws_cloudwatch_event_rule.every_fifteen_minutes.name}"
    target_id = "${aws_lambda_function.viz_wrds_api_handler.function_name}"
    arn = "${aws_lambda_function.viz_wrds_api_handler.arn}"
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_check_lambda" {
    statement_id = "AllowExecutionFromCloudWatch"
    action = "lambda:InvokeFunction"
    function_name = "${aws_lambda_function.viz_wrds_api_handler.function_name}"
    principal = "events.amazonaws.com"
    source_arn = "${aws_cloudwatch_event_rule.every_fifteen_minutes.arn}"
}

resource "aws_lambda_function_event_invoke_config" "viz_wrds_api_handler" {
  function_name = resource.aws_lambda_function.viz_wrds_api_handler.function_name
  maximum_retry_attempts = 0
  destination_config {
    on_failure {
      destination = var.email_sns_topics["viz_lambda_errors"].arn
    }
  }
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
      CACHE_DAYS         = 1
      MAX_FLOWS_BUCKET   = var.max_flows_bucket
      DB_INGEST_FUNCTION =	aws_lambda_function.viz_db_ingest.arn
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

resource "aws_lambda_function_event_invoke_config" "viz_max_flows" {
  function_name = resource.aws_lambda_function.viz_max_flows.function_name
  maximum_retry_attempts = 0
  destination_config {
    on_failure {
      destination = var.email_sns_topics["viz_lambda_errors"].arn
    }
  }
}

################################
## Inundation Parent Function ##
################################

resource "aws_lambda_function" "viz_inundation_parent" {
  function_name = "viz_inundation_parent_${var.environment}"
  description   = "Lambda function to process NWM data and kick off HUC inundation lambdas for each HUC with streams above bankfull threshold"
  memory_size   = 2048
  timeout       = 900

  environment {
    variables = {
      EMPTY_RASTER_BUCKET         = var.fim_data_bucket
      EMPTY_RASTER_MRF_PREFIX     = "empty_rasters/mrf"
      FIM_DATA_BUCKET             = var.fim_data_bucket
      FIM_VERSION                 = var.fim_version
      NWM_DATA_BUCKET             = var.nwm_data_bucket
      PROCESSED_OUTPUT_BUCKET     = var.fim_output_bucket
      PROCESSED_OUTPUT_PREFIX     = "processing_outputs"
      VIZ_AUTHORITATIVE_BUCKET    = var.viz_authoritative_bucket
      VIZ_DB_DATABASE	            = var.viz_db_name
      VIZ_DB_HOST	                = var.viz_db_host
      VIZ_DB_PASSWORD	            = jsondecode(var.viz_db_user_secret_string)["password"]
      VIZ_DB_USERNAME	            = jsondecode(var.viz_db_user_secret_string)["username"]
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
    var.viz_lambda_shared_funcs_layer,
    var.psycopg2_sqlalchemy_layer
  ]

  tags = {
    "Name" = "viz_inundation_parent_${var.environment}"
  }

  vpc_config {
  	security_group_ids = var.db_lambda_security_groups
  	subnet_ids = var.db_lambda_subnets
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

resource "aws_lambda_function_event_invoke_config" "viz_inundation_parent" {
  function_name = resource.aws_lambda_function.viz_inundation_parent.function_name
  maximum_retry_attempts = 0
  destination_config {
    on_failure {
      destination = var.email_sns_topics["viz_lambda_errors"].arn
    }
  }
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
      VIZ_DB_DATABASE	             = var.viz_db_name
      VIZ_DB_HOST	                 = var.viz_db_host
      VIZ_DB_PASSWORD	             = jsondecode(var.viz_db_user_secret_string)["password"]
      VIZ_DB_USERNAME	             = jsondecode(var.viz_db_user_secret_string)["username"]
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
    var.viz_lambda_shared_funcs_layer,
    var.psycopg2_sqlalchemy_layer
  ]

  tags = {
    "Name" = "viz_huc_inundation_processing_${var.environment}"
  }

  vpc_config {
  	security_group_ids = var.db_lambda_security_groups
  	subnet_ids = var.db_lambda_subnets
  }
}

resource "aws_lambda_function_event_invoke_config" "viz_huc_inundation_processing" {
  function_name = resource.aws_lambda_function.viz_huc_inundation_processing.function_name
  maximum_retry_attempts = 0
  destination_config {
    on_failure {
      destination = var.email_sns_topics["viz_lambda_errors"].arn
    }
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

resource "aws_lambda_function_event_invoke_config" "viz_optimize_rasters_destinations" {
  function_name = resource.aws_lambda_function.viz_optimize_rasters.function_name
  maximum_retry_attempts = 0
  destination_config {
    on_failure {
      destination = var.email_sns_topics["viz_lambda_errors"].arn
    }
  }
}

############################
## Viz DB Ingest Function ##
############################

resource "aws_lambda_function" "viz_db_ingest" {
  function_name = "viz_db_ingest_${var.environment}"
  description   = "Lambda function to manage the loading of datasets into the Viz Processing database. Requires db_ingest_worker to delegate files to."
  memory_size   = 256
  timeout       = 900
  vpc_config {
  	security_group_ids = var.db_lambda_security_groups
  	subnet_ids = var.db_lambda_subnets
  }
  environment {
    variables = {
      BACKLOAD_BATCH_SIZE	= 100
      MAX_WORKERS         = 500
      MRF_TIMESTEP        = 3
      VIZ_DB_DATABASE     = var.viz_db_name
      VIZ_DB_HOST         = var.viz_db_host
      VIZ_DB_USERNAME     = jsondecode(var.viz_db_user_secret_string)["username"]
      VIZ_DB_PASSWORD     = jsondecode(var.viz_db_user_secret_string)["password"]
      WORKER_LAMBDA_NAME  = resource.aws_lambda_function.viz_db_ingest_worker.function_name
    }
  }
  s3_bucket = var.lambda_data_bucket
  s3_key    = "viz/lambda_functions/viz_db_ingest.zip"
  runtime = "python3.7"
  handler = "lambda_function.lambda_handler"
  role = var.lambda_role
  layers = [
    var.psycopg2_sqlalchemy_layer,
    var.es_logging_layer,
    var.viz_lambda_shared_funcs_layer
  ]
  
  tags = {
    "Name" = "viz_db_ingest_${var.environment}"
  }
}

resource "aws_sns_topic_subscription" "viz_db_ingest_subscriptions" {
  for_each  = local.db_ingest_subscriptions
  topic_arn = var.sns_topics["${each.value}"].arn
  protocol  = "lambda"
  endpoint  = resource.aws_lambda_function.viz_db_ingest.arn
}

resource "aws_lambda_permission" "viz_db_ingest_permissions" {
  for_each      = local.db_ingest_subscriptions
  action        = "lambda:InvokeFunction"
  function_name = resource.aws_lambda_function.viz_db_ingest.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.sns_topics["${each.value}"].arn
}

resource "aws_lambda_function_event_invoke_config" "viz_db_ingest_destinations" {
  function_name = resource.aws_lambda_function.viz_db_ingest.function_name
  maximum_retry_attempts = 0
  destination_config {
    on_success {
      destination = var.sns_topics["viz_db_postprocess"].arn
    }

    on_failure {
      destination = var.email_sns_topics["viz_lambda_errors"].arn
    }
  }
}

###############################
## DB Ingest Worker Function ##
###############################

resource "aws_lambda_function" "viz_db_ingest_worker" {
  function_name = "viz_db_ingest_worker_${var.environment}"
  description   = "Worker function to load individual files into the Viz Processing database."
  memory_size   = 1280
  timeout       = 900
  vpc_config {
  	security_group_ids = var.db_lambda_security_groups
  	subnet_ids = var.db_lambda_subnets
  }
  environment {
    variables = {
      VIZ_DB_DATABASE = var.viz_db_name
      VIZ_DB_HOST = var.viz_db_host
      VIZ_DB_USERNAME = jsondecode(var.viz_db_user_secret_string)["username"]
      VIZ_DB_PASSWORD = jsondecode(var.viz_db_user_secret_string)["password"]
    }
  }
  s3_bucket = var.lambda_data_bucket
  s3_key    = "viz/lambda_functions/viz_db_ingest_worker.zip"
  runtime = "python3.7"
  handler = "lambda_function.lambda_handler"
  role = var.lambda_role
  layers = [
    var.xarray_layer,
    var.psycopg2_sqlalchemy_layer,
    var.viz_lambda_shared_funcs_layer
  ]
  
  tags = {
    "Name" = "viz_db_ingest_worker_${var.environment}"
  }
}

resource "aws_lambda_function_event_invoke_config" "viz_db_ingest_worker_destinations" {
  function_name = resource.aws_lambda_function.viz_db_ingest_worker.function_name
  maximum_retry_attempts = 0
}

#############################
## DB Postprocess Function ##
#############################

resource "aws_lambda_function" "viz_db_postprocess" {
  function_name = "viz_db_postprocess_${var.environment}"
  description   = "Lambda function to run viz postprocessing on already-ingested data sources, copy publish tables to egis rds, and publish services."
  memory_size   = 1536
  timeout       = 900
  vpc_config {
  	security_group_ids = var.db_lambda_security_groups
  	subnet_ids = var.db_lambda_subnets
  }
  environment {
    variables = {
      EGIS_DB_DATABASE = var.egis_db_name
      EGIS_DB_HOST = var.egis_db_host
      EGIS_DB_USERNAME = jsondecode(var.egis_db_secret_string)["username"]
      EGIS_DB_PASSWORD = jsondecode(var.egis_db_secret_string)["password"]
      GIS_PASSWORD = var.egis_portal_password
      GIS_HOST = local.egis_host
      GIS_USERNAME = "hydrovis.proc"
      PUBLISH_FLAG_BUCKET = var.max_flows_bucket
      S3_BUCKET = var.viz_authoritative_bucket
      SD_S3_PATH = "viz/db_pipeline/pro_project_data/sd_files/"
      SERVICE_TAG = local.service_suffix
      VIZ_DB_DATABASE = var.viz_db_name
      VIZ_DB_HOST = var.viz_db_host
      VIZ_DB_USERNAME = jsondecode(var.viz_db_user_secret_string)["username"]
      VIZ_DB_PASSWORD = jsondecode(var.viz_db_user_secret_string)["password"]
    }
  }
  s3_bucket = var.lambda_data_bucket
  s3_key    = "viz/lambda_functions/viz_db_postprocess.zip"
  runtime = "python3.7"
  handler = "lambda_function.lambda_handler"
  role = var.lambda_role
  layers = [
    var.arcgis_python_api_layer,
    var.psycopg2_sqlalchemy_layer,
    var.xarray_layer,
    var.es_logging_layer,
    var.viz_lambda_shared_funcs_layer
  ]
  tags = {
    "Name" = "viz_db_postprocess_${var.environment}"
  }
}

resource "aws_sns_topic_subscription" "viz_db_postprocess_subscription" {
  topic_arn = var.sns_topics["viz_db_postprocess"].arn
  protocol  = "lambda"
  endpoint  = resource.aws_lambda_function.viz_db_postprocess.arn
}

resource "aws_lambda_permission" "viz_db_postprocess_permissions" {
  action        = "lambda:InvokeFunction"
  function_name = resource.aws_lambda_function.viz_db_postprocess.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.sns_topics["viz_db_postprocess"].arn
}

resource "aws_lambda_function_event_invoke_config" "viz_db_postprocess_destinations" {
  function_name = resource.aws_lambda_function.viz_db_postprocess.function_name
  maximum_retry_attempts = 0
  destination_config {
    on_failure {
      destination = var.email_sns_topics["viz_lambda_errors"].arn
    }
  }
}

#####################

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

output "db_ingest" {
  value = aws_lambda_function.viz_db_ingest
}

output "db_ingest_worker" {
  value = aws_lambda_function.viz_db_ingest_worker
}

output "db_postprocess" {
  value = aws_lambda_function.viz_db_postprocess
}

output "wrds_api_handler" {
  value = aws_lambda_function.viz_wrds_api_handler
}