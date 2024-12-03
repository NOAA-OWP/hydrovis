terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      configuration_aliases = [ aws.sns ]
    }
  }
}

variable "environment" {
  description = "Hydrovis environment"
  type        = string
}

variable "account_id" {
  description = "Hydrovis environment"
  type        = string
}

variable "region" {
  description = "Hydrovis environment"
  type        = string
}

variable "viz_authoritative_bucket" {
  description = "S3 bucket where the viz authoritative data will live."
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

variable "deployment_bucket" {
  description = "S3 buckets where the lambda zip files will live."
  type        = string
}

variable "python_preprocessing_bucket" {
  description = "S3 bucket where the outputted max flows will live."
  type        = string
}

variable "rnr_data_bucket" {
  description = "S3 bucket where the rnr max flows will live."
  type        = string
}

variable "viz_cache_bucket" {
  description = "S3 bucket where the viz cache shapefiles will live."
  type        = string
}

variable "fim_version" {
  description = "Version of the FIM Package"
  type        = string
}

variable "hand_version" {
  description = "Version of HAND FIM"
  type        = string
}

variable "lambda_role" {
  description = "Role to use for the lambda functions."
  type        = string
}

variable "db_lambda_security_groups" {
  description = "Security group for db-pipeline lambdas."
  type        = list(any)
}

variable "db_lambda_subnets" {
  description = "Subnets to use for the db-pipeline lambdas."
  type        = list(any)
}

# variable "sns_topics" {
#   description = "SnS topics"
#   type        = map(any)
# }

variable "nws_shared_account_nwm_sns" {
  type = string
}

variable "wrds_db_dump_sns" {
  type = string
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

variable "viz_db_suser_secret_string" {
  description = "The secret string of the viz_processing data base superuser to write/read data as."
  type        = string
}

variable "egis_db_user_secret_string" {
  description = "The secret string for the egis rds database."
  type        = string
}

variable "wrds_db_host" {
  description = "Hostname of the viz processing RDS instance."
  type        = string
}

variable "wrds_db_user_secret_string" {
  description = "The secret string of the viz_processing data base user to write/read data as."
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

variable "pandas_layer" {
  type = string
}

variable "geopandas_layer" {
  type = string
}

variable "psycopg2_sqlalchemy_layer" {
  type = string
}

variable "arcgis_python_api_layer" {
  type = string
}

variable "requests_layer" {
  type = string
}

variable "yaml_layer" {
  type = string
}

variable "dask_layer" {
  type = string
}

variable "viz_lambda_shared_funcs_layer" {
  type = string
}

variable "viz_pipeline_step_function_arn" {
  type = string
}

variable "sync_wrds_db_step_function_arn" {
  type = string
}

variable "default_tags" {
  type = map(string)
}

variable "nwm_dataflow_version" {
  type = string
}

variable "five_minute_trigger" {
  type = object({
    name = string,
    arn = string
  })
}

########################################################################################################################################
########################################################################################################################################

locals {
  egis_host                = var.environment == "prod" ? "https://maps.water.noaa.gov/portal" : var.environment == "uat" ? "https://maps-staging.water.noaa.gov/portal" : var.environment == "ti" ? "https://maps-testing.water.noaa.gov/portal" : "https://hydrovis-dev.nwc.nws.noaa.gov/portal"
  service_suffix           = var.environment == "prod" ? "" : var.environment == "uat" ? "_beta" : var.environment == "ti" ? "_alpha" : "_gamma"
  raster_output_prefix     = "processing_outputs"
  ecr_repository_image_tag = "latest"
  ingest_flow_threshold    = 0.001

  initialize_pipeline_subscriptions = toset([
    "rnr_wrf_hydro_output"
  ])
}

##################################
## EGIS Health Checker Function ##
##################################
data "archive_file" "egis_health_checker_zip" {
  type = "zip"

  source_file = "${path.module}/egis_health_checker/lambda_function.py"

  output_path = "${path.module}/temp/egis_health_checker_${var.environment}_${var.region}.zip"
}

resource "aws_s3_object" "egis_health_checker_zip_upload" {
  provider = aws.no_tags
  
  bucket      = var.deployment_bucket
  key         = "terraform_artifacts/${path.module}/egis_health_checker.zip"
  source      = data.archive_file.egis_health_checker_zip.output_path
  source_hash = filemd5(data.archive_file.egis_health_checker_zip.output_path)
}

resource "aws_lambda_function" "egis_health_checker" {
  function_name = "hv-vpp-${var.environment}-egis-health-checker"
  description   = "Lambda function to ping WRDS API and format outputs for processing."
  memory_size   = 512
  timeout       = 300

  vpc_config {
    security_group_ids = var.db_lambda_security_groups
    subnet_ids         = var.db_lambda_subnets
  }

  environment {
    variables = {
      GIS_HOST = var.environment == "prod" ? "maps.water.noaa.gov" : var.environment == "uat" ? "maps-staging.water.noaa.gov" : var.environment == "ti" ? "maps-testing.water.noaa.gov" : "hydrovis-dev.nwc.nws.noaa.gov"
    }
  }
  s3_bucket        = aws_s3_object.egis_health_checker_zip_upload.bucket
  s3_key           = aws_s3_object.egis_health_checker_zip_upload.key
  source_code_hash = filebase64sha256(data.archive_file.egis_health_checker_zip.output_path)
  runtime          = "python3.9"
  handler          = "lambda_function.lambda_handler"
  role             = var.lambda_role
  layers = [
    var.requests_layer
  ]
  tags = {
    "Name" = "hv-vpp-${var.environment}-egis-health-checker"
  }
}

resource "aws_cloudwatch_event_target" "check_lambda_every_five_minutes_egis_health_checker" {
  rule      = var.five_minute_trigger.name
  target_id = aws_lambda_function.egis_health_checker.function_name
  arn       = aws_lambda_function.egis_health_checker.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_check_lambda_egis_health_checker" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.egis_health_checker.function_name
  principal     = "events.amazonaws.com"
  source_arn    = var.five_minute_trigger.arn
}

resource "aws_lambda_function_event_invoke_config" "egis_health_checker" {
  function_name          = resource.aws_lambda_function.egis_health_checker.function_name
  maximum_retry_attempts = 0
  destination_config {
    on_failure {
      destination = var.email_sns_topics["egis_healthcheck_errors"].arn
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "egis_healthcheck_errors" {
  alarm_name                = "${var.environment}_egis_healthcheck"
  comparison_operator       = "GreaterThanOrEqualToThreshold"
  datapoints_to_alarm       = 1
  evaluation_periods        = 1

  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 600
  statistic           = "Sum"
  threshold           = 2
  treat_missing_data   = "notBreaching"

  dimensions = {
    FunctionName = resource.aws_lambda_function.egis_health_checker.function_name
  }
}

###################################
## Python Preprocessing Function ##
###################################
data "archive_file" "python_preprocessing_zip" {
  type = "zip"

  source_dir = "${path.module}/viz_python_preprocessing"

  output_path = "${path.module}/temp/viz_python_preprocessing_${var.environment}_${var.region}.zip"
}

resource "aws_s3_object" "python_preprocessing_zip_upload" {
  provider = aws.no_tags
  
  bucket      = var.deployment_bucket
  key         = "terraform_artifacts/${path.module}/viz_python_preprocessing.zip"
  source      = data.archive_file.python_preprocessing_zip.output_path
  source_hash = filemd5(data.archive_file.python_preprocessing_zip.output_path)
}

#########################
#### 3GB RAM Version ####
#########################
resource "aws_lambda_function" "viz_python_preprocessing_3GB" {
  function_name = "hv-vpp-${var.environment}-viz-python-preprocessing"
  description   = "Lambda function to create max streamflow files for NWM data"
  memory_size   = 3072
  ephemeral_storage {
    size = 10240
  }
  timeout = 900

  vpc_config {
    security_group_ids = var.db_lambda_security_groups
    subnet_ids         = var.db_lambda_subnets
  }

  environment {
    variables = {
      CACHE_DAYS            = 1
      AUTH_DATA_BUCKET      = var.viz_authoritative_bucket
      DATA_BUCKET_UPLOAD    = var.fim_output_bucket
      VIZ_DB_DATABASE       = var.viz_db_name
      VIZ_DB_HOST           = var.viz_db_host
      VIZ_DB_USERNAME       = jsondecode(var.viz_db_user_secret_string)["username"]
      VIZ_DB_PASSWORD       = jsondecode(var.viz_db_user_secret_string)["password"]
      NWM_DATAFLOW_VERSION  = var.nwm_dataflow_version
    }
  }
  s3_bucket        = aws_s3_object.python_preprocessing_zip_upload.bucket
  s3_key           = aws_s3_object.python_preprocessing_zip_upload.key
  source_code_hash = filebase64sha256(data.archive_file.python_preprocessing_zip.output_path)

  runtime = "python3.9"
  handler = "lambda_function.lambda_handler"

  role = var.lambda_role

  layers = [
    var.xarray_layer,
    var.psycopg2_sqlalchemy_layer,
    var.viz_lambda_shared_funcs_layer,
    var.requests_layer,
    var.dask_layer
  ]

  tags = {
    "Name" = "hv-vpp-${var.environment}-viz-python-preprocessing-3GB"
  }
}

#########################
#### 10GB RAM Version ####
#########################
resource "aws_lambda_function" "viz_python_preprocessing_10GB" {
  function_name = "hv-vpp-${var.environment}-viz-python-preprocessing-10GB"
  description   = "Lambda function to create max streamflow files for NWM data"
  memory_size   = 10240
  ephemeral_storage {
    size = 10240
  }
  timeout = 900

  vpc_config {
    security_group_ids = var.db_lambda_security_groups
    subnet_ids         = var.db_lambda_subnets
  }

  environment {
    variables = {
      CACHE_DAYS            = 1
      AUTH_DATA_BUCKET      = var.viz_authoritative_bucket
      DATA_BUCKET_UPLOAD    = var.fim_output_bucket
      VIZ_DB_DATABASE       = var.viz_db_name
      VIZ_DB_HOST           = var.viz_db_host
      VIZ_DB_USERNAME       = jsondecode(var.viz_db_user_secret_string)["username"]
      VIZ_DB_PASSWORD       = jsondecode(var.viz_db_user_secret_string)["password"]
      NWM_DATAFLOW_VERSION  = var.nwm_dataflow_version
    }
  }
  s3_bucket        = aws_s3_object.python_preprocessing_zip_upload.bucket
  s3_key           = aws_s3_object.python_preprocessing_zip_upload.key
  source_code_hash = filebase64sha256(data.archive_file.python_preprocessing_zip.output_path)

  runtime = "python3.9"
  handler = "lambda_function.lambda_handler"

  role = var.lambda_role

  layers = [
    var.xarray_layer,
    var.psycopg2_sqlalchemy_layer,
    var.viz_lambda_shared_funcs_layer,
    var.requests_layer,
    var.dask_layer
  ]

  tags = {
    "Name" = "hv-vpp-${var.environment}-viz-python-preprocessing-10GB"
  }
}

#############################
##   Initialize Pipeline   ##
#############################
data "archive_file" "initialize_pipeline_zip" {
  type = "zip"

  source_dir = "${path.module}/viz_initialize_pipeline"

  output_path = "${path.module}/temp/viz_initialize_pipeline_${var.environment}_${var.region}.zip"
}

resource "aws_s3_object" "initialize_pipeline_zip_upload" {
  provider = aws.no_tags
  
  bucket      = var.deployment_bucket
  key         = "terraform_artifacts/${path.module}/viz_initialize_pipeline.zip"
  source      = data.archive_file.initialize_pipeline_zip.output_path
  source_hash = filemd5(data.archive_file.initialize_pipeline_zip.output_path)
}

resource "aws_lambda_function" "viz_initialize_pipeline" {
  function_name = "hv-vpp-${var.environment}-viz-initialize-pipeline"
  description   = "Lambda function to receive automatic input from sns or lambda invocation, parse the event, construct a pipeline dictionary, and invoke the viz pipeline state machine with it."
  memory_size   = 128
  timeout       = 300
  vpc_config {
    security_group_ids = var.db_lambda_security_groups
    subnet_ids         = var.db_lambda_subnets
  }
  environment {
    variables = {
      SF_ARN__VIZ_PIPELINE         = var.viz_pipeline_step_function_arn
      SF_ARN__SYNC_WRDS_DB         = var.sync_wrds_db_step_function_arn
      SNS_TOPIC__WRDS_DB_DUMP      = var.wrds_db_dump_sns
      DATA_BUCKET_UPLOAD           = var.fim_output_bucket
      PYTHON_PREPROCESSING_BUCKET  = var.python_preprocessing_bucket
      RNR_DATA_BUCKET              = var.rnr_data_bucket
      RASTER_OUTPUT_BUCKET         = var.fim_output_bucket
      RASTER_OUTPUT_PREFIX         = local.raster_output_prefix
      INGEST_FLOW_THRESHOLD        = local.ingest_flow_threshold
      VIZ_DB_DATABASE              = var.viz_db_name
      VIZ_DB_HOST                  = var.viz_db_host
      VIZ_DB_USERNAME              = jsondecode(var.viz_db_user_secret_string)["username"]
      VIZ_DB_PASSWORD              = jsondecode(var.viz_db_user_secret_string)["password"]
      NWM_DATAFLOW_VERSION         = var.nwm_dataflow_version
    }
  }
  s3_bucket        = aws_s3_object.initialize_pipeline_zip_upload.bucket
  s3_key           = aws_s3_object.initialize_pipeline_zip_upload.key
  source_code_hash = filebase64sha256(data.archive_file.initialize_pipeline_zip.output_path)
  runtime          = "python3.9"
  handler          = "lambda_function.lambda_handler"
  role             = var.lambda_role
  layers = [
    var.yaml_layer,
    var.viz_lambda_shared_funcs_layer,
    var.pandas_layer
  ]
  tags = {
    "Name" = "hv-vpp-${var.environment}-viz-initialize-pipeline"
  }
}

resource "aws_sns_topic_subscription" "viz_initialize_pipeline_subscription_shared_nwm" {
  count     = var.environment == "ti" ? 0 : 1
  provider = aws.sns
  topic_arn = var.nws_shared_account_nwm_sns
  protocol  = "lambda"
  endpoint  = resource.aws_lambda_function.viz_initialize_pipeline.arn
}

resource "aws_lambda_permission" "viz_initialize_pipeline_permissions_shared_nwm" {
  count     = var.environment == "ti" ? 0 : 1
  action        = "lambda:InvokeFunction"
  function_name = resource.aws_lambda_function.viz_initialize_pipeline.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.nws_shared_account_nwm_sns
}

resource "aws_sns_topic_subscription" "viz_initialize_pipeline_subscription_wrds_db_dump" {
  provider = aws.sns
  topic_arn = var.wrds_db_dump_sns
  protocol  = "lambda"
  endpoint  = resource.aws_lambda_function.viz_initialize_pipeline.arn
}

resource "aws_lambda_permission" "viz_initialize_pipeline_permissions_wrds_db_dump" {
  action        = "lambda:InvokeFunction"
  function_name = resource.aws_lambda_function.viz_initialize_pipeline.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.wrds_db_dump_sns
}

resource "aws_lambda_function_event_invoke_config" "viz_initialize_pipeline_destinations" {
  function_name          = resource.aws_lambda_function.viz_initialize_pipeline.function_name
  maximum_retry_attempts = 0
  destination_config {
    on_failure {
      destination = var.email_sns_topics["viz_lambda_errors"].arn
    }
  }
}

#############################
##   DB Postprocess SQL    ##
#############################
data "archive_file" "db_postprocess_sql_zip" {
  type = "zip"

  source_dir = "${path.module}/viz_db_postprocess_sql"

  output_path = "${path.module}/temp/viz_db_postprocess_sql_${var.environment}_${var.region}.zip"
}

resource "aws_s3_object" "db_postprocess_sql_zip_upload" {
  provider = aws.no_tags
  
  bucket      = var.deployment_bucket
  key         = "terraform_artifacts/${path.module}/viz_db_postprocess_sql.zip"
  source      = data.archive_file.db_postprocess_sql_zip.output_path
  source_hash = filemd5(data.archive_file.db_postprocess_sql_zip.output_path)
}

resource "aws_lambda_function" "viz_db_postprocess_sql" {
  function_name = "hv-vpp-${var.environment}-viz-db-postprocess-sql"
  description   = "Lambda function to run arg-driven sql code against the viz database."
  memory_size   = 128
  timeout       = 900
  vpc_config {
    security_group_ids = var.db_lambda_security_groups
    subnet_ids         = var.db_lambda_subnets
  }
  environment {
    variables = {
      VIZ_DB_DATABASE       = var.viz_db_name
      VIZ_DB_HOST           = var.viz_db_host
      VIZ_DB_USERNAME       = jsondecode(var.viz_db_user_secret_string)["username"]
      VIZ_DB_PASSWORD       = jsondecode(var.viz_db_user_secret_string)["password"]
      FIM_VERSION           = var.fim_version
      HAND_VERSION          = var.hand_version
    }
  }
  s3_bucket        = aws_s3_object.db_postprocess_sql_zip_upload.bucket
  s3_key           = aws_s3_object.db_postprocess_sql_zip_upload.key
  source_code_hash = filebase64sha256(data.archive_file.db_postprocess_sql_zip.output_path)
  runtime          = "python3.9"
  handler          = "lambda_function.lambda_handler"
  role             = var.lambda_role
  layers = [
    var.psycopg2_sqlalchemy_layer,
    var.viz_lambda_shared_funcs_layer
  ]
  tags = {
    "Name" = "hv-vpp-${var.environment}-viz-db-postprocess-sql"
  }
}

resource "aws_lambda_function_event_invoke_config" "viz_db_postprocess_sql_destinations" {
  function_name          = resource.aws_lambda_function.viz_db_postprocess_sql.function_name
  maximum_retry_attempts = 0
  destination_config {
    on_failure {
      destination = var.email_sns_topics["viz_lambda_errors"].arn
    }
  }
}

#############################
##        DB Ingest        ##
#############################
data "archive_file" "db_ingest_zip" {
  type = "zip"

  source_file = "${path.module}/viz_db_ingest/lambda_function.py"

  output_path = "${path.module}/temp/viz_db_ingest_${var.environment}_${var.region}.zip"
}

resource "aws_s3_object" "db_ingest_zip_upload" {
  provider = aws.no_tags
  
  bucket      = var.deployment_bucket
  key         = "terraform_artifacts/${path.module}/viz_db_ingest.zip"
  source      = data.archive_file.db_ingest_zip.output_path
  source_hash = filemd5(data.archive_file.db_ingest_zip.output_path)
}

resource "aws_lambda_function" "viz_db_ingest" {
  function_name = "hv-vpp-${var.environment}-viz-db-ingest"
  description   = "Lambda function to ingest individual files into the viz processing postgresql database."
  memory_size   = 2560
  timeout       = 900
  vpc_config {
    security_group_ids = var.db_lambda_security_groups
    subnet_ids         = var.db_lambda_subnets
  }
  environment {
    variables = {
      VIZ_DB_DATABASE = var.viz_db_name
      VIZ_DB_HOST     = var.viz_db_host
      VIZ_DB_USERNAME = jsondecode(var.viz_db_user_secret_string)["username"]
      VIZ_DB_PASSWORD = jsondecode(var.viz_db_user_secret_string)["password"]
    }
  }
  s3_bucket        = aws_s3_object.db_ingest_zip_upload.bucket
  s3_key           = aws_s3_object.db_ingest_zip_upload.key
  source_code_hash = filebase64sha256(data.archive_file.db_ingest_zip.output_path)
  runtime          = "python3.9"
  handler          = "lambda_function.lambda_handler"
  role             = var.lambda_role
  layers = [
    var.psycopg2_sqlalchemy_layer,
    var.xarray_layer,
    var.requests_layer,
    var.viz_lambda_shared_funcs_layer
  ]
  tags = {
    "Name" = "hv-vpp-${var.environment}-viz-db-ingest"
  }
}

resource "aws_lambda_function_event_invoke_config" "viz_db_ingest_destinations" {
  function_name          = resource.aws_lambda_function.viz_db_ingest.function_name
  maximum_retry_attempts = 0
  destination_config {
    on_failure {
      destination = var.email_sns_topics["viz_lambda_errors"].arn
    }
  }
}

#############################
##      FIM Data Prep      ##
#############################
data "archive_file" "fim_data_prep_zip" {
  type = "zip"

  source_dir = "${path.module}/viz_fim_data_prep"

  output_path = "${path.module}/temp/viz_fim_data_prep_${var.environment}_${var.region}.zip"
}

resource "aws_s3_object" "fim_data_prep_zip_upload" {
  provider = aws.no_tags
  
  bucket      = var.deployment_bucket
  key         = "terraform_artifacts/${path.module}/viz_fim_data_prep.zip"
  source      = data.archive_file.fim_data_prep_zip.output_path
  source_hash = filemd5(data.archive_file.fim_data_prep_zip.output_path)
}

resource "aws_lambda_function" "viz_fim_data_prep" {
  function_name = "hv-vpp-${var.environment}-viz-fim-data-prep"
  description   = "Lambda function to setup a fim run by retriving max flows from the database, prepare an ingest database table, and creating a dictionary for huc-based worker lambdas to use."
  memory_size   = var.environment == "ti" ? 4096 : 2048 # Larger for apocalyptic testing
  timeout       = 900
  vpc_config {
    security_group_ids = var.db_lambda_security_groups
    subnet_ids         = var.db_lambda_subnets
  }
  environment {
    variables = {
      EGIS_DB_DATABASE        = var.egis_db_name
      EGIS_DB_HOST            = var.egis_db_host
      EGIS_DB_USERNAME        = jsondecode(var.egis_db_user_secret_string)["username"]
      EGIS_DB_PASSWORD        = jsondecode(var.egis_db_user_secret_string)["password"]
      PROCESSED_OUTPUT_BUCKET = var.fim_output_bucket
      PROCESSED_OUTPUT_PREFIX = "processing_outputs"
      FIM_VERSION             = var.fim_version
      VIZ_DB_DATABASE         = var.viz_db_name
      VIZ_DB_HOST             = var.viz_db_host
      VIZ_DB_USERNAME         = jsondecode(var.viz_db_user_secret_string)["username"]
      VIZ_DB_PASSWORD         = jsondecode(var.viz_db_user_secret_string)["password"]
    }
  }
  s3_bucket        = aws_s3_object.fim_data_prep_zip_upload.bucket
  s3_key           = aws_s3_object.fim_data_prep_zip_upload.key
  source_code_hash = filebase64sha256(data.archive_file.fim_data_prep_zip.output_path)
  runtime          = "python3.9"
  handler          = "lambda_function.lambda_handler"
  role             = var.lambda_role
  layers = [
    var.psycopg2_sqlalchemy_layer,
    var.xarray_layer,
    var.es_logging_layer,
    var.viz_lambda_shared_funcs_layer
  ]
  tags = {
    "Name" = "hv-vpp-${var.environment}-viz-fim-data-prep"
  }
}

resource "aws_lambda_function_event_invoke_config" "viz_fim_data_prep_destinations" {
  function_name          = resource.aws_lambda_function.viz_fim_data_prep.function_name
  maximum_retry_attempts = 0
  destination_config {
    on_failure {
      destination = var.email_sns_topics["viz_lambda_errors"].arn
    }
  }
}

#############################
##    Update EGIS Data     ##
#############################
data "archive_file" "update_egis_data_zip" {
  type = "zip"

  source_file = "${path.module}/viz_update_egis_data/lambda_function.py"

  output_path = "${path.module}/temp/viz_update_egis_data_${var.environment}_${var.region}.zip"
}

resource "aws_s3_object" "update_egis_data_zip_upload" {
  provider = aws.no_tags
  
  bucket      = var.deployment_bucket
  key         = "terraform_artifacts/${path.module}/viz_update_egis_data.zip"
  source      = data.archive_file.update_egis_data_zip.output_path
  source_hash = filemd5(data.archive_file.update_egis_data_zip.output_path)
}

resource "aws_lambda_function" "viz_update_egis_data" {
  function_name = "hv-vpp-${var.environment}-viz-update-egis-data"
  description   = "Lambda function to copy a postprocesses service table into the egis postgreql database, as well as cache data in the viz database."
  memory_size   = 128
  timeout       = 900
  vpc_config {
    security_group_ids = var.db_lambda_security_groups
    subnet_ids         = var.db_lambda_subnets
  }
  environment {
    variables = {
      EGIS_DB_DATABASE = var.egis_db_name
      EGIS_DB_HOST     = var.egis_db_host
      EGIS_DB_USERNAME = jsondecode(var.egis_db_user_secret_string)["username"]
      EGIS_DB_PASSWORD = jsondecode(var.egis_db_user_secret_string)["password"]
      VIZ_DB_DATABASE  = var.viz_db_name
      VIZ_DB_HOST      = var.viz_db_host
      VIZ_DB_USERNAME  = jsondecode(var.viz_db_user_secret_string)["username"]
      VIZ_DB_PASSWORD  = jsondecode(var.viz_db_user_secret_string)["password"]
      CACHE_BUCKET     = var.viz_cache_bucket
    }
  }
  s3_bucket        = aws_s3_object.update_egis_data_zip_upload.bucket
  s3_key           = aws_s3_object.update_egis_data_zip_upload.key
  source_code_hash = filebase64sha256(data.archive_file.update_egis_data_zip.output_path)
  runtime          = "python3.9"
  handler          = "lambda_function.lambda_handler"
  role             = var.lambda_role
  layers = [
    var.pandas_layer,
    var.psycopg2_sqlalchemy_layer,
    var.viz_lambda_shared_funcs_layer
  ]
  tags = {
    "Name" = "hv-vpp-${var.environment}-viz-update-egis-data"
  }
}

resource "aws_lambda_function_event_invoke_config" "viz_update_egis_data_destinations" {
  function_name          = resource.aws_lambda_function.viz_update_egis_data.function_name
  maximum_retry_attempts = 0
  destination_config {
    on_failure {
      destination = var.email_sns_topics["viz_lambda_errors"].arn
    }
  }
}

#############################
##     Publish Service     ##
#############################
data "archive_file" "publish_service_zip" {
  type = "zip"

  source_dir = "${path.module}/viz_publish_service"

  output_path = "${path.module}/temp/viz_publish_service_${var.environment}_${var.region}.zip"
}

resource "aws_s3_object" "publish_service_zip_upload" {
  provider = aws.no_tags
  
  bucket      = var.deployment_bucket
  key         = "terraform_artifacts/${path.module}/viz_publish_service.zip"
  source      = data.archive_file.publish_service_zip.output_path
  source_hash = filemd5(data.archive_file.publish_service_zip.output_path)
}

resource "aws_s3_object" "viz_publish_mapx_files" {
  provider = aws.no_tags
  
  for_each    = fileset("${path.module}/viz_publish_service/services", "**/*.mapx")
  bucket      = var.deployment_bucket
  key         = "viz_mapx/${reverse(split("/",each.key))[0]}"
  source      = "${path.module}/viz_publish_service/services/${each.key}"
  source_hash = filemd5("${path.module}/viz_publish_service/services/${each.key}")
}

resource "aws_lambda_function" "viz_publish_service" {
  function_name = "hv-vpp-${var.environment}-viz-publish-service"
  description   = "Lambda function to check and publish (if needed) an egis service based on a SD file in S3."
  memory_size   = 1024
  timeout       = 600
  vpc_config {
    security_group_ids = var.db_lambda_security_groups
    subnet_ids         = var.db_lambda_subnets
  }
  environment {
    variables = {
      GIS_PASSWORD        = var.egis_portal_password
      GIS_HOST            = local.egis_host
      GIS_USERNAME        = "hydrovis.proc"
      PUBLISH_FLAG_BUCKET = var.python_preprocessing_bucket
      S3_BUCKET           = var.viz_authoritative_bucket
      SD_S3_PATH          = "viz_sd_files"
      SERVICE_TAG         = local.service_suffix
      EGIS_DB_HOST        = var.egis_db_host
      EGIS_DB_DATABASE    = var.egis_db_name
      EGIS_DB_USERNAME    = jsondecode(var.egis_db_user_secret_string)["username"]
      EGIS_DB_PASSWORD    = jsondecode(var.egis_db_user_secret_string)["password"]
      ENVIRONMENT         = var.environment
    }
  }
  s3_bucket        = aws_s3_object.publish_service_zip_upload.bucket
  s3_key           = aws_s3_object.publish_service_zip_upload.key
  source_code_hash = filebase64sha256(data.archive_file.publish_service_zip.output_path)
  runtime          = "python3.9"
  handler          = "lambda_function.lambda_handler"
  role             = var.lambda_role
  layers = [
    var.yaml_layer,
    var.arcgis_python_api_layer,
    var.viz_lambda_shared_funcs_layer
  ]
  tags = {
    "Name" = "hv-vpp-${var.environment}-viz-publish-service"
  }
}

resource "aws_lambda_function_event_invoke_config" "viz_publish_service_destinations" {
  function_name          = resource.aws_lambda_function.viz_publish_service.function_name
  maximum_retry_attempts = 0
  destination_config {
    on_failure {
      destination = var.email_sns_topics["viz_lambda_errors"].arn
    }
  }
}


######################
## VIZ TEST WRDS DB ##
######################
data "archive_file" "viz_test_wrds_db_zip" {
  type = "zip"
  output_path = "${path.module}/temp/test_sql_${var.environment}_${var.region}.zip"

  source {
    content  = file("${path.module}/viz_test_wrds_db/lambda_function.py")
    filename = "lambda_function.py"
  }

  dynamic "source" {
    for_each = fileset("${path.module}", "**/*.sql")
    content {
      content  = file("${path.module}/${source.key}")
      filename = "sql_files/${basename(source.key)}"
    }
  }
}

resource "aws_s3_object" "viz_test_wrds_db_upload" {
  provider = aws.no_tags
  
  bucket      = var.deployment_bucket
  key         = "terraform_artifacts/${path.module}/viz_update_egis_data.zip"
  source      = data.archive_file.viz_test_wrds_db_zip.output_path
  source_hash = filemd5(data.archive_file.viz_test_wrds_db_zip.output_path)
}

resource "aws_lambda_function" "viz_test_wrds_db" {
  function_name = "hv-vpp-${var.environment}-viz-test-wrds-db"
  description   = "Lambda function to test the wrds_location3_ondeck db before it is swapped for the live version"
  timeout       = 900
  memory_size   = 5000
  vpc_config {
    security_group_ids = var.db_lambda_security_groups
    subnet_ids         = var.db_lambda_subnets
  }
  environment {
    variables = {
      WRDS_DB_HOST      = var.wrds_db_host
      WRDS_DB_USERNAME  = jsondecode(var.wrds_db_user_secret_string)["username"]
      WRDS_DB_PASSWORD  = jsondecode(var.wrds_db_user_secret_string)["password"]
      VIZ_DB_DATABASE   = var.viz_db_name
      VIZ_DB_HOST       = var.viz_db_host
      VIZ_DB_USERNAME   = jsondecode(var.viz_db_suser_secret_string)["username"]
      VIZ_DB_PASSWORD   = jsondecode(var.viz_db_suser_secret_string)["password"]
    }
  }
  s3_bucket        = aws_s3_object.viz_test_wrds_db_upload.bucket
  s3_key           = aws_s3_object.viz_test_wrds_db_upload.key
  source_code_hash = filebase64sha256(data.archive_file.viz_test_wrds_db_zip.output_path)
  runtime          = "python3.9"
  handler          = "lambda_function.lambda_handler"
  role             = var.lambda_role
  layers = [
    var.psycopg2_sqlalchemy_layer,
    var.viz_lambda_shared_funcs_layer
  ]
  tags = {
    "Name" = "hv-vpp-${var.environment}-viz-test-wrds-db"
  }
}



#########################
## Image Based Lambdas ##
#########################

module "image-based-lambdas" {
  source = "./image_based"

  environment                 = var.environment
  account_id                  = var.account_id
  region                      = var.region
  deployment_bucket           = var.deployment_bucket
  python_preprocessing_bucket = var.python_preprocessing_bucket
  lambda_role                 = var.lambda_role
  hand_fim_processing_sgs     = var.db_lambda_security_groups
  hand_fim_processing_subnets = var.db_lambda_subnets
  ecr_repository_image_tag    = local.ecr_repository_image_tag
  fim_version                 = var.fim_version
  hand_version                = var.hand_version
  fim_data_bucket             = var.fim_data_bucket
  viz_db_name                 = var.viz_db_name
  viz_db_host                 = var.viz_db_host
  viz_db_user_secret_string   = var.viz_db_user_secret_string
  egis_db_name                = var.egis_db_name
  egis_db_host                = var.egis_db_host
  egis_db_user_secret_string  = var.egis_db_user_secret_string
  default_tags                = var.default_tags
  nwm_dataflow_version        = var.nwm_dataflow_version
}

########################################################################################################################################
########################################################################################################################################

output "python_preprocessing_3GB" {
  value = aws_lambda_function.viz_python_preprocessing_3GB
}

output "python_preprocessing_10GB" {
  value = aws_lambda_function.viz_python_preprocessing_10GB
}

output "initialize_pipeline" {
  value = aws_lambda_function.viz_initialize_pipeline
}

output "db_postprocess_sql" {
  value = aws_lambda_function.viz_db_postprocess_sql
}

output "db_ingest" {
  value = aws_lambda_function.viz_db_ingest
}

output "fim_data_prep" {
  value = aws_lambda_function.viz_fim_data_prep
}

output "update_egis_data" {
  value = aws_lambda_function.viz_update_egis_data
}

output "publish_service" {
  value = aws_lambda_function.viz_publish_service
}

output "egis_health_checker" {
  value = aws_lambda_function.egis_health_checker
}

output "test_wrds_db" {
  value = aws_lambda_function.viz_test_wrds_db
}

output "hand_fim_processing" {
  value = module.image-based-lambdas.hand_fim_processing
}

output "schism_fim" {
  value = module.image-based-lambdas.schism_fim
}

output "optimize_rasters" {
  value = module.image-based-lambdas.optimize_rasters
}

output "raster_processing" {
  value = module.image-based-lambdas.raster_processing
}

output "egis_healthcheck_alarm" {
  value = aws_cloudwatch_metric_alarm.egis_healthcheck_errors
}