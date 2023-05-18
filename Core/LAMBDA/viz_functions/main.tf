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

variable "max_flows_bucket" {
  description = "S3 bucket where the outputted max flows will live."
  type        = string
}

variable "viz_cache_bucket" {
  description = "S3 bucket where the viz cache shapefiles will live."
  type        = string
}

variable "fim_version" {
  description = "FIM version to run"
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

variable "nat_sg_group" {
  type = string
}

variable "db_lambda_subnets" {
  description = "Subnets to use for the db-pipeline lambdas."
  type        = list(any)
}

variable "sns_topics" {
  description = "SnS topics"
  type        = map(any)
}

variable "nws_shared_account_nwm_sns" {
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

variable "egis_db_user_secret_string" {
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

variable "pandas_layer" {
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

variable "viz_lambda_shared_funcs_layer" {
  type = string
}

variable "dataservices_ip" {
  type = string
}

########################################################################################################################################
########################################################################################################################################
data "aws_caller_identity" "current" {}

locals {
  egis_host      = var.environment == "prod" ? "https://maps.water.noaa.gov/portal" : var.environment == "uat" ? "https://maps-staging.water.noaa.gov/portal" : var.environment == "ti" ? "https://maps-testing.water.noaa.gov/portal" : "https://hydrovis-dev.nwc.nws.noaa.gov/portal"
  service_suffix = var.environment == "prod" ? "" : var.environment == "uat" ? "_beta" : var.environment == "ti" ? "_alpha" : "_gamma"
  raster_output_prefix = "processing_outputs"
  ecr_repository_image_tag = "latest"

  initialize_pipeline_subscriptions = toset([
    "rnr_max_flows"
  ])
}

########################################################################################################################################
########################################################################################################################################

###############################
## WRDS API Handler Function ##
###############################
data "archive_file" "wrds_api_handler_zip" {
  type = "zip"

  source_file = "${path.module}/viz_wrds_api_handler/lambda_function.py"

  output_path = "${path.module}/viz_wrds_api_handler_${var.environment}.zip"
}

resource "aws_s3_object" "wrds_api_handler_zip_upload" {
  bucket      = var.deployment_bucket
  key         = "viz/viz_wrds_api_handler.zip"
  source      = data.archive_file.wrds_api_handler_zip.output_path
  source_hash = filemd5(data.archive_file.wrds_api_handler_zip.output_path)
}

resource "aws_lambda_function" "viz_wrds_api_handler" {
  function_name = "viz_wrds_api_handler_${var.environment}"
  description   = "Lambda function to ping WRDS API and format outputs for processing."
  memory_size   = 512
  timeout       = 900
  vpc_config {
    security_group_ids = [var.nat_sg_group]
    subnet_ids         = var.db_lambda_subnets
  }
  environment {
    variables = {
      DATASERVICES_HOST                 = var.dataservices_ip
      PROCESSED_OUTPUT_BUCKET           = var.max_flows_bucket
      PROCESSED_OUTPUT_PREFIX           = "max_stage/ahps"
      INITIALIZE_PIPELINE_FUNCTION      = aws_lambda_function.viz_initialize_pipeline.arn
    }
  }
  s3_bucket        = aws_s3_object.wrds_api_handler_zip_upload.bucket
  s3_key           = aws_s3_object.wrds_api_handler_zip_upload.key
  source_code_hash = filebase64sha256(data.archive_file.wrds_api_handler_zip.output_path)
  runtime          = "python3.9"
  handler          = "lambda_function.lambda_handler"
  role             = var.lambda_role
  layers = [
    var.arcgis_python_api_layer,
    var.es_logging_layer,
    var.viz_lambda_shared_funcs_layer
  ]
  tags = {
    "Name" = "viz_wrds_api_handler_${var.environment}"
  }
}

resource "aws_cloudwatch_event_rule" "every_five_minutes" {
  name                = "every_five_minutes"
  description         = "Fires every five minutes"
  schedule_expression = "cron(0/5 * * * ? *)"
}

resource "aws_cloudwatch_event_target" "check_lambda_every_five_minutes" {
  rule      = aws_cloudwatch_event_rule.every_five_minutes.name
  target_id = aws_lambda_function.viz_wrds_api_handler.function_name
  arn       = aws_lambda_function.viz_wrds_api_handler.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_check_lambda" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.viz_wrds_api_handler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_five_minutes.arn
}

resource "aws_lambda_function_event_invoke_config" "viz_wrds_api_handler" {
  function_name          = resource.aws_lambda_function.viz_wrds_api_handler.function_name
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
data "archive_file" "max_flows_zip" {
  type = "zip"

  source_file = "${path.module}/viz_max_flows/lambda_function.py"

  output_path = "${path.module}/viz_max_flows_${var.environment}.zip"
}

resource "aws_s3_object" "max_flows_zip_upload" {
  bucket      = var.deployment_bucket
  key         = "viz/viz_max_flows.zip"
  source      = data.archive_file.max_flows_zip.output_path
  source_hash = filemd5(data.archive_file.max_flows_zip.output_path)
}

resource "aws_lambda_function" "viz_max_flows" {
  function_name = "viz_max_flows_${var.environment}"
  description   = "Lambda function to create max streamflow files for NWM data"
  memory_size   = 2048
  ephemeral_storage {
    size = 1024
  }
  timeout       = 900

  vpc_config {
    security_group_ids = var.db_lambda_security_groups
    subnet_ids         = var.db_lambda_subnets
  }

  environment {
    variables = {
      CACHE_DAYS         = 1
      MAX_VALS_BUCKET   = var.max_flows_bucket
      INITIALIZE_PIPELINE_FUNCTION = aws_lambda_function.viz_initialize_pipeline.arn
      VIZ_DB_DATABASE     = var.viz_db_name
      VIZ_DB_HOST         = var.viz_db_host
      VIZ_DB_USERNAME     = jsondecode(var.viz_db_user_secret_string)["username"]
      VIZ_DB_PASSWORD     = jsondecode(var.viz_db_user_secret_string)["password"]
      DATA_BUCKET_UPLOAD  = var.fim_data_bucket
    }
  }
  s3_bucket        = aws_s3_object.max_flows_zip_upload.bucket
  s3_key           = aws_s3_object.max_flows_zip_upload.key
  source_code_hash = filebase64sha256(data.archive_file.max_flows_zip.output_path)

  runtime = "python3.9"
  handler = "lambda_function.lambda_handler"

  role = var.lambda_role

  layers = [
    var.xarray_layer,
    var.psycopg2_sqlalchemy_layer,
    var.viz_lambda_shared_funcs_layer,
    var.requests_layer,
  ]

  tags = {
    "Name" = "viz_max_flows_${var.environment}"
  }
}

#############################
##   Initialize Pipeline   ##
#############################
data "archive_file" "initialize_pipeline_zip" {
  type = "zip"

  source_file = "${path.module}/viz_initialize_pipeline/lambda_function.py"

  output_path = "${path.module}/viz_initialize_pipeline_${var.environment}.zip"
}

resource "aws_s3_object" "initialize_pipeline_zip_upload" {
  bucket      = var.deployment_bucket
  key         = "viz/viz_initialize_pipeline.zip"
  source      = data.archive_file.initialize_pipeline_zip.output_path
  source_hash = filemd5(data.archive_file.initialize_pipeline_zip.output_path)
}

resource "aws_lambda_function" "viz_initialize_pipeline" {
  function_name = "viz_initialize_pipeline_${var.environment}"
  description   = "Lambda function to receive automatic input from sns or lambda invocation, parse the event, construct a pipeline dictionary, and invoke the viz pipeline state machine with it."
  memory_size   = 128
  timeout       = 300
  vpc_config {
    security_group_ids = var.db_lambda_security_groups
    subnet_ids         = var.db_lambda_subnets
  }
  environment {
    variables = {
      STEP_FUNCTION_ARN   = aws_sfn_state_machine.viz_pipeline_step_function.arn
      VIZ_DB_DATABASE     = var.viz_db_name
      VIZ_DB_HOST         = var.viz_db_host
      VIZ_DB_USERNAME     = jsondecode(var.viz_db_user_secret_string)["username"]
      VIZ_DB_PASSWORD     = jsondecode(var.viz_db_user_secret_string)["password"]
      DATA_BUCKET_UPLOAD  = var.fim_data_bucket
    }
  }
  s3_bucket        = aws_s3_object.initialize_pipeline_zip_upload.bucket
  s3_key           = aws_s3_object.initialize_pipeline_zip_upload.key
  source_code_hash = filebase64sha256(data.archive_file.initialize_pipeline_zip.output_path)
  runtime          = "python3.9"
  handler          = "lambda_function.lambda_handler"
  role             = var.lambda_role
  layers = [
    var.psycopg2_sqlalchemy_layer,
    var.viz_lambda_shared_funcs_layer,
    var.pandas_layer
  ]
  tags = {
    "Name" = "viz_initialize_pipeline_${var.environment}"
  }
}

resource "aws_sns_topic_subscription" "viz_initialize_pipeline_subscriptions" {
  for_each  = local.initialize_pipeline_subscriptions
  topic_arn = var.sns_topics["${each.value}"].arn
  protocol  = "lambda"
  endpoint  = resource.aws_lambda_function.viz_initialize_pipeline.arn
}

resource "aws_lambda_permission" "viz_initialize_pipeline_permissions" {
  for_each      = local.initialize_pipeline_subscriptions
  action        = "lambda:InvokeFunction"
  function_name = resource.aws_lambda_function.viz_initialize_pipeline.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.sns_topics["${each.value}"].arn
}

resource "aws_sns_topic_subscription" "viz_initialize_pipeline_subscription_shared_nwm" {
  topic_arn = var.nws_shared_account_nwm_sns
  protocol  = "lambda"
  endpoint  = resource.aws_lambda_function.viz_initialize_pipeline.arn
}

resource "aws_lambda_permission" "viz_initialize_pipeline_permissions_shared_nwm" {
  action        = "lambda:InvokeFunction"
  function_name = resource.aws_lambda_function.viz_initialize_pipeline.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.nws_shared_account_nwm_sns
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

  output_path = "${path.module}/viz_db_postprocess_sql_${var.environment}.zip"
}

resource "aws_s3_object" "db_postprocess_sql_zip_upload" {
  bucket      = var.deployment_bucket
  key         = "viz/viz_db_postprocess_sql.zip"
  source      = data.archive_file.db_postprocess_sql_zip.output_path
  source_hash = filemd5(data.archive_file.db_postprocess_sql_zip.output_path)
}

resource "aws_lambda_function" "viz_db_postprocess_sql" {
  function_name = "viz_db_postprocess_sql_${var.environment}"
  description   = "Lambda function to run arg-driven sql code against the viz database."
  memory_size   = 128
  timeout       = 900
  vpc_config {
    security_group_ids = var.db_lambda_security_groups
    subnet_ids         = var.db_lambda_subnets
  }
  environment {
    variables = {
      VIZ_DB_DATABASE     = var.viz_db_name
      VIZ_DB_HOST         = var.viz_db_host
      VIZ_DB_USERNAME     = jsondecode(var.viz_db_user_secret_string)["username"]
      VIZ_DB_PASSWORD     = jsondecode(var.viz_db_user_secret_string)["password"]
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
    "Name" = "viz_db_postprocess_sql_${var.environment}"
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

  output_path = "${path.module}/viz_db_ingest_${var.environment}.zip"
}

resource "aws_s3_object" "db_ingest_zip_upload" {
  bucket      = var.deployment_bucket
  key         = "viz/viz_db_ingest.zip"
  source      = data.archive_file.db_ingest_zip.output_path
  source_hash = filemd5(data.archive_file.db_ingest_zip.output_path)
}

resource "aws_lambda_function" "viz_db_ingest" {
  function_name = "viz_db_ingest_${var.environment}"
  description   = "Lambda function to ingest individual files into the viz processing postgresql database."
  memory_size   = 1280
  timeout       = 900
  vpc_config {
    security_group_ids = var.db_lambda_security_groups
    subnet_ids         = var.db_lambda_subnets
  }
  environment {
    variables = {
      VIZ_DB_DATABASE     = var.viz_db_name
      VIZ_DB_HOST         = var.viz_db_host
      VIZ_DB_USERNAME     = jsondecode(var.viz_db_user_secret_string)["username"]
      VIZ_DB_PASSWORD     = jsondecode(var.viz_db_user_secret_string)["password"]
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
    "Name" = "viz_db_ingest_${var.environment}"
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

  output_path = "${path.module}/viz_fim_data_prep_${var.environment}.zip"
}

resource "aws_s3_object" "fim_data_prep_zip_upload" {
  bucket      = var.deployment_bucket
  key         = "viz/viz_fim_data_prep.zip"
  source      = data.archive_file.fim_data_prep_zip.output_path
  source_hash = filemd5(data.archive_file.fim_data_prep_zip.output_path)
}

resource "aws_lambda_function" "viz_fim_data_prep" {
  function_name = "viz_fim_data_prep_${var.environment}"
  description   = "Lambda function to setup a fim run by retriving max flows from the database, prepare an ingest database table, and creating a dictionary for huc-based worker lambdas to use."
  memory_size   = 2048
  timeout       = 900
  vpc_config {
    security_group_ids = var.db_lambda_security_groups
    subnet_ids         = var.db_lambda_subnets
  }
  environment {
    variables = {
      EGIS_DB_DATABASE    = var.egis_db_name
      EGIS_DB_HOST        = var.egis_db_host
      EGIS_DB_USERNAME    = jsondecode(var.egis_db_user_secret_string)["username"]
      EGIS_DB_PASSWORD    = jsondecode(var.egis_db_user_secret_string)["password"]
      FIM_DATA_BUCKET             = var.fim_data_bucket
      FIM_VERSION                 = var.fim_version
      PROCESSED_OUTPUT_BUCKET     = var.fim_output_bucket
      PROCESSED_OUTPUT_PREFIX     = "processing_outputs"
      VIZ_DB_DATABASE             = var.viz_db_name
      VIZ_DB_HOST                 = var.viz_db_host
      VIZ_DB_USERNAME             = jsondecode(var.viz_db_user_secret_string)["username"]
      VIZ_DB_PASSWORD             = jsondecode(var.viz_db_user_secret_string)["password"]
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
    "Name" = "viz_fim_data_prep_${var.environment}"
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

  output_path = "${path.module}/viz_update_egis_data_${var.environment}.zip"
}

resource "aws_s3_object" "update_egis_data_zip_upload" {
  bucket      = var.deployment_bucket
  key         = "viz/viz_update_egis_data.zip"
  source      = data.archive_file.update_egis_data_zip.output_path
  source_hash = filemd5(data.archive_file.update_egis_data_zip.output_path)
}

resource "aws_lambda_function" "viz_update_egis_data" {
  function_name = "viz_update_egis_data_${var.environment}"
  description   = "Lambda function to copy a postprocesses service table into the egis postgreql database, as well as cache data in the viz database."
  memory_size   = 128
  timeout       = 900
  vpc_config {
    security_group_ids = var.db_lambda_security_groups
    subnet_ids         = var.db_lambda_subnets
  }
  environment {
    variables = {
      EGIS_DB_DATABASE    = var.egis_db_name
      EGIS_DB_HOST        = var.egis_db_host
      EGIS_DB_USERNAME    = jsondecode(var.egis_db_user_secret_string)["username"]
      EGIS_DB_PASSWORD    = jsondecode(var.egis_db_user_secret_string)["password"]
      VIZ_DB_DATABASE     = var.viz_db_name
      VIZ_DB_HOST         = var.viz_db_host
      VIZ_DB_USERNAME     = jsondecode(var.viz_db_user_secret_string)["username"]
      VIZ_DB_PASSWORD     = jsondecode(var.viz_db_user_secret_string)["password"]
      CACHE_BUCKET        = var.viz_cache_bucket
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
    "Name" = "viz_update_egis_data_${var.environment}"
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

  source_file = "${path.module}/viz_publish_service/lambda_function.py"

  output_path = "${path.module}/viz_publish_service_${var.environment}.zip"
}

resource "aws_s3_object" "publish_service_zip_upload" {
  bucket      = var.deployment_bucket
  key         = "viz/viz_publish_service.zip"
  source      = data.archive_file.publish_service_zip.output_path
  source_hash = filemd5(data.archive_file.publish_service_zip.output_path)
}

resource "aws_lambda_function" "viz_publish_service" {
  function_name = "viz_publish_service_${var.environment}"
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
      PUBLISH_FLAG_BUCKET = var.max_flows_bucket
      S3_BUCKET           = var.viz_authoritative_bucket
      SD_S3_PATH          = "viz/db_pipeline/pro_project_data/sd_files/"
      SERVICE_TAG         = local.service_suffix
    }
  }
  s3_bucket        = aws_s3_object.publish_service_zip_upload.bucket
  s3_key           = aws_s3_object.publish_service_zip_upload.key
  source_code_hash = filebase64sha256(data.archive_file.publish_service_zip.output_path)
  runtime          = "python3.9"
  handler          = "lambda_function.lambda_handler"
  role             = var.lambda_role
  layers = [
    var.arcgis_python_api_layer,
    var.viz_lambda_shared_funcs_layer
  ]
  tags = {
    "Name" = "viz_publish_service_${var.environment}"
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

#########################
## Image Based Lambdas ##
#########################

module "image_based_lambdas" {
  source = "./image_based"

  environment = var.environment
  account_id  = var.account_id
  region      = var.region
  deployment_bucket = var.deployment_bucket
  max_flows_bucket = var.max_flows_bucket
  raster_output_bucket = var.fim_output_bucket
  raster_output_prefix = local.raster_output_prefix
  lambda_role = var.lambda_role
  huc_processing_sgs = var.db_lambda_security_groups
  huc_processing_subnets = var.db_lambda_subnets
  ecr_repository_image_tag = local.ecr_repository_image_tag
  fim_version = var.fim_version
  fim_data_bucket = var.fim_data_bucket
  viz_db_name = var.viz_db_name
  viz_db_host = var.viz_db_host
  viz_db_user_secret_string = var.viz_db_user_secret_string
  egis_db_name = var.egis_db_name
  egis_db_host = var.egis_db_host
  egis_db_user_secret_string = var.egis_db_user_secret_string
}

########################################################################################################################################
########################################################################################################################################
##################################################
##     Viz Process Schism FIM Step Function     ##
##################################################

resource "aws_sfn_state_machine" "schism_fim_processing_step_function" {
  name     = "process_schism_fim_${var.environment}"
  role_arn = var.lambda_role

  definition = <<EOF
{
  "Comment": "Processes the outputs for all SCHISM FIM services.",
  "StartAt": "Prepare for SCHISM FIM Processing",
  "States": {
    "Prepare for SCHISM FIM Processing": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "arn:aws:lambda:${var.region}:${var.account_id}:function:${module.image_based_lambdas.schism_fim_processing}",
        "Payload": {
          "step": "setup",
          "args.$": "$"
        }
      },
      "Retry": [
        {
          "ErrorEquals": [
            "States.ALL"
          ],
          "IntervalSeconds": 1,
          "MaxAttempts": 2,
          "BackoffRate": 2
        }
      ],
      "Next": "Iterate over HUC8s",
      "ResultPath": "$.result",
      "ResultSelector": {
        "huc_list.$": "$.Payload"
      }
    },
    "Iterate over HUC8s": {
      "Type": "Map",
      "ItemProcessor": {
        "ProcessorConfig": {
          "Mode": "INLINE"
        },
        "StartAt": "Process FIM By HUC8",
        "States": {
          "Process FIM By HUC8": {
            "Type": "Task",
            "Resource": "arn:aws:states:::lambda:invoke",
            "Parameters": {
              "FunctionName": "arn:aws:lambda:${var.region}:${var.account_id}:function:${module.image_based_lambdas.schism_fim_processing}",
              "Payload": {
                "step": "iteration",
                "args": {
                  "huc.$": "$.huc8",
                  "reference_time.$": "$.reference_time",
                  "configuration.$": "$.configuration"
                }
              }
            },
            "Retry": [
              {
                "ErrorEquals": [
                  "States.ALL"
                ],
                "IntervalSeconds": 1,
                "MaxAttempts": 2,
                "BackoffRate": 2
              }
            ],
            "Next": "Choice",
            "ResultPath": "$.result",
            "ResultSelector": {
              "output_bucket.$": "$.Payload.output_bucket",
              "output_raster.$": "$.Payload.output_key"
            }
          },
          "Choice": {
            "Type": "Choice",
            "Choices": [
              {
                "Not": {
                  "Variable": "$.result.output_raster",
                  "IsNull": true
                },
                "Next": "Cloud Optimize Raster"
              }
            ],
            "Default": "Success"
          },
          "Success": {
            "Type": "Succeed"
          },
          "Cloud Optimize Raster": {
            "Type": "Task",
            "Resource": "arn:aws:states:::lambda:invoke",
            "Parameters": {
              "FunctionName": "arn:aws:lambda:${var.region}:${var.account_id}:function:${module.image_based_lambdas.optimize_rasters}",
              "Payload.$": "$"
            },
            "Retry": [
              {
                "ErrorEquals": [
                  "Lambda.ServiceException",
                  "Lambda.AWSLambdaException",
                  "Lambda.SdkClientException",
                  "Lambda.TooManyRequestsException"
                ],
                "IntervalSeconds": 2,
                "MaxAttempts": 6,
                "BackoffRate": 2
              }
            ],
            "Next": "Success",
            "InputPath": "$.result",
            "ResultPath": null,
            "OutputPath": "$.result"
          }
        }
      },
      "ItemsPath": "$.result.huc_list",
      "ItemSelector": {
        "huc8.$": "$$.Map.Item.Value",
        "reference_time.$": "$.reference_time",
        "configuration.$": "$.configuration"
      },
      "Next": "Move Rasters to Published Folder",
      "ResultPath": "$.result"
    },
    "Move Rasters to Published Folder": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "OutputPath": "$.Payload",
      "Parameters": {
        "FunctionName": "${aws_lambda_function.viz_update_egis_data.arn}",
        "Payload": {
          "step": "update_service_data",
          "args": {
            "map_item.$": "States.Format('{}_inundation_depth', $.configuration)",
            "reference_time.$": "$.reference_time",
            "job_type.$": "$.job_type",
            "service": {
              "service.$": "$.configuration",
              "configuration.$": "$.service.configuration",
              "egis_server": "image"
            },
            "output_raster_info_list.$": "$.result"
          }
        }
      },
      "Retry": [
        {
          "ErrorEquals": [
            "Lambda.ServiceException",
            "Lambda.AWSLambdaException",
            "Lambda.SdkClientException",
            "Lambda.TooManyRequestsException"
          ],
          "IntervalSeconds": 2,
          "MaxAttempts": 6,
          "BackoffRate": 2
        }
      ],
      "End": true
    }
  }
}
EOF
}

########################################################################################################################################
########################################################################################################################################
########################################
##     Viz Pipeline Step Function     ##
########################################

resource "aws_sfn_state_machine" "viz_pipeline_step_function" {
  name     = "viz_pipeline_${var.environment}"
  role_arn = var.lambda_role

  definition = <<EOF
{
  "Comment": "A description of my state machine",
  "StartAt": "Input Data Groups",
  "States": {
    "Input Data Groups": {
      "Type": "Map",
      "Next": "Max Flows Processing",
      "Iterator": {
        "StartAt": "Postprocess SQL - Input Data Prep",
        "States": {
          "Postprocess SQL - Input Data Prep": {
            "Type": "Task",
            "Resource": "arn:aws:states:::lambda:invoke",
            "Parameters": {
              "Payload": {
                "args.$": "$",
                "step": "ingest_prep",
                "folder": "admin"
              },
              "FunctionName": "${aws_lambda_function.viz_db_postprocess_sql.arn}"
            },
            "Retry": [
              {
                "ErrorEquals": [
                  "Lambda.ServiceException",
                  "Lambda.AWSLambdaException",
                  "Lambda.SdkClientException"
                ],
                "IntervalSeconds": 2,
                "MaxAttempts": 6,
                "BackoffRate": 2,
                "Comment": "Lambda Service Errors"
              }
            ],
            "Next": "Input Data Files",
            "ResultPath": null
          },
          "Input Data Files": {
            "Type": "Map",
            "Iterator": {
              "StartAt": "Input Data Checker/Ingester",
              "States": {
                "Input Data Checker/Ingester": {
                  "Type": "Task",
                  "Resource": "arn:aws:states:::lambda:invoke",
                  "OutputPath": "$.Payload",
                  "Parameters": {
                    "Payload.$": "$",
                    "FunctionName": "${aws_lambda_function.viz_db_ingest.arn}"
                  },
                  "End": true,
                  "Retry": [
                    {
                      "ErrorEquals": [
                        "MissingS3FileException"
                      ],
                      "BackoffRate": 1,
                      "IntervalSeconds": 120,
                      "MaxAttempts": 35,
                      "Comment": "Missing S3 File"
                    },
                    {
                      "ErrorEquals": [
                        "Lambda.ServiceException",
                        "Lambda.AWSLambdaException",
                        "Lambda.SdkClientException"
                      ],
                      "IntervalSeconds": 2,
                      "MaxAttempts": 6,
                      "BackoffRate": 2,
                      "Comment": "Lambda Service Errors"
                    }
                  ]
                }
              }
            },
            "ResultPath": null,
            "Next": "Postprocess SQL - Input Data Prep Finish",
            "Parameters": {
              "file.$": "$$.Map.Item.Value.file",
              "target_table.$": "$.map.target_table",
              "bucket.$": "$.map.bucket",
              "reference_time.$": "$.map.reference_time",
              "keep_flows_at_or_above.$": "$.map.keep_flows_at_or_above"
            },
            "ItemsPath": "$.map.ingest_datasets"
          },
          "Postprocess SQL - Input Data Prep Finish": {
            "Type": "Task",
            "Resource": "arn:aws:states:::lambda:invoke",
            "Parameters": {
              "Payload": {
                "args.$": "$",
                "step": "ingest_finish",
                "folder": "admin"
              },
              "FunctionName": "${aws_lambda_function.viz_db_postprocess_sql.arn}"
            },
            "Retry": [
              {
                "ErrorEquals": [
                  "Lambda.ServiceException",
                  "Lambda.AWSLambdaException",
                  "Lambda.SdkClientException"
                ],
                "IntervalSeconds": 2,
                "MaxAttempts": 6,
                "BackoffRate": 2,
                "Comment": "Lambda Service Errors"
              }
            ],
            "End": true,
            "ResultPath": null
          }
        }
      },
      "ResultPath": null,
      "ItemsPath": "$.ingest_groups",
      "Parameters": {
        "map.$": "$$.Map.Item.Value",
        "sql_rename_dict.$": "$.pipeline_info.sql_rename_dict"
      }
    },
    "Max Flows Processing": {
      "Type": "Map",
      "Next": "Services Processing",
      "Iterator": {
        "StartAt": "Postprocess SQL - Max Flows",
        "States": {
          "Postprocess SQL - Max Flows": {
            "Type": "Task",
            "Resource": "arn:aws:states:::lambda:invoke",
            "OutputPath": "$.Payload",
            "Parameters": {
              "FunctionName": "${aws_lambda_function.viz_db_postprocess_sql.arn}",
              "Payload": {
                "args": {
                  "map.$": "$",
                  "sql_rename_dict.$": "$.sql_rename_dict"
                },
                "step": "max_flows",
                "folder": "max_flows"
              }
            },
            "Retry": [
              {
                "ErrorEquals": [
                  "Lambda.ServiceException",
                  "Lambda.AWSLambdaException",
                  "Lambda.SdkClientException"
                ],
                "IntervalSeconds": 2,
                "MaxAttempts": 6,
                "BackoffRate": 2,
                "Comment": "Lambda Service Errors"
              }
            ],
            "End": true
          }
        }
      },
      "ResultPath": null,
      "ItemsPath": "$.pipeline_info.max_flows",
      "Parameters": {
        "map_item.$": "$$.Map.Item.Value",
        "max_flows.$": "$$.Map.Item.Value",
        "reference_time.$": "$.pipeline_info.reference_time",
        "sql_rename_dict.$": "$.pipeline_info.sql_rename_dict"
      },
      "MaxConcurrency": 5
    },
    "Services Processing": {
      "Type": "Map",
      "Iterator": {
        "StartAt": "FIM vs Non-FIM Services",
        "States": {
          "FIM vs Non-FIM Services": {
            "Type": "Choice",
            "Choices": [
              {
                "Variable": "$.service.fim_service",
                "BooleanEquals": true,
                "Comment": "FIM Processing",
                "Next": "FIM Config Processing"
              }
            ],
            "Default": "Vector vs Raster"
          },
          "Vector vs Raster": {
            "Type": "Choice",
            "Choices": [
              {
                "Variable": "$.service.egis_server",
                "StringEquals": "image",
                "Comment": "Raster Processing",
                "Next": "Raster Processing"
              }
            ],
            "Default": "Postprocess SQL - Service"
          },
          "Raster Processing": {
            "Type": "Task",
            "Resource": "arn:aws:states:::lambda:invoke",
            "Parameters": {
              "Payload.$": "$",
              "FunctionName": "arn:aws:lambda:${var.region}:${var.account_id}:function:${module.image_based_lambdas.raster_processing}"
            },
            "Retry": [
              {
                "ErrorEquals": [
                  "Lambda.ServiceException",
                  "Lambda.AWSLambdaException",
                  "Lambda.SdkClientException"
                ],
                "IntervalSeconds": 2,
                "MaxAttempts": 6,
                "BackoffRate": 2,
                "Comment": "Lambda Service Errors"
              }
            ],
            "Next": "Map",
            "OutputPath": "$.Payload"
          },
          "Map": {
            "Type": "Map",
            "Next": "Postprocess SQL - Service",
            "Iterator": {
              "StartAt": "Optimize Rasters",
              "States": {
                "Optimize Rasters": {
                  "Type": "Task",
                  "Resource": "arn:aws:states:::lambda:invoke",
                  "OutputPath": "$.Payload",
                  "Parameters": {
                    "Payload.$": "$",
                    "FunctionName": "arn:aws:lambda:${var.region}:${var.account_id}:function:${module.image_based_lambdas.optimize_rasters}"
                  },
                  "Retry": [
                    {
                      "ErrorEquals": [
                        "Lambda.ServiceException",
                        "Lambda.AWSLambdaException",
                        "Lambda.SdkClientException"
                      ],
                      "IntervalSeconds": 2,
                      "MaxAttempts": 6,
                      "BackoffRate": 2,
                      "Comment": "Lambda Service Errors"
                    }
                  ],
                  "End": true
                }
              }
            },
            "ItemsPath": "$.output_rasters",
            "Parameters": {
              "output_raster.$": "$$.Map.Item.Value",
              "service.$": "$.service",
              "reference_time.$": "$.reference_time",
              "map_item.$": "$.map_item",
              "job_type.$": "$.job_type",
              "output_bucket.$": "$.output_bucket"
            },
            "ResultPath": null
          },
          "FIM Config Processing": {
            "Type": "Map",
            "Next": "Parallelize Summaries",
            "Iterator": {
              "StartAt": "Choice",
              "States": {
                "Choice": {
                  "Type": "Choice",
                  "Choices": [
                    {
                      "Variable": "$.fim_config",
                      "StringMatches": "*coastal*",
                      "Next": "Process Coastal (SCHISM) FIM"
                    }
                  ],
                  "Default": "FIM Data Preparation - Setup HUC Branch Data"
                },
                "Process Coastal (SCHISM) FIM": {
                  "Type": "Task",
                  "Resource": "arn:aws:states:::states:startExecution.sync:2",
                  "Parameters": {
                    "StateMachineArn": "${aws_sfn_state_machine.schism_fim_processing_step_function.arn}",
                    "Input": {
                      "configuration.$": "$.fim_config",
                      "reference_time.$": "$.reference_time",
                      "job_type.$": "$.job_type",
                      "service.$": "$.service"
                    }
                  },
                  "Next": "Add \"_inundation\" to $.map_item (",
                  "ResultPath": null
                },
                "Add \"_inundation\" to $.map_item (": {
                  "Type": "Pass",
                  "Next": "Add \"_inundation\" to $.map_item (1)",
                  "Parameters": {
                    "input.$": "$",
                    "mods": {
                      "map_item.$": "States.Format('{}_inundation', $.map_item)"
                    }
                  }
                },
                "Add \"_inundation\" to $.map_item (1)": {
                  "Type": "Pass",
                  "Next": "Update EGIS Data - FIM Config",
                  "Parameters": {
                    "output.$": "States.JsonMerge($.input, $.mods, false)"
                  },
                  "OutputPath": "$.output"
                },
                "FIM Data Preparation - Setup HUC Branch Data": {
                  "Type": "Task",
                  "Resource": "arn:aws:states:::lambda:invoke",
                  "Parameters": {
                    "FunctionName": "${aws_lambda_function.viz_fim_data_prep.arn}",
                    "Payload": {
                      "args.$": "$",
                      "step": "setup_branch_iteration"
                    }
                  },
                  "Retry": [
                    {
                      "ErrorEquals": [
                        "Lambda.ServiceException",
                        "Lambda.AWSLambdaException",
                        "Lambda.SdkClientException"
                      ],
                      "IntervalSeconds": 2,
                      "MaxAttempts": 6,
                      "BackoffRate": 2,
                      "Comment": "Lambda Service Errors"
                    }
                  ],
                  "Next": "HUC Processing Map",
                  "ResultPath": "$.huc_processing_payload",
                  "ResultSelector": {
                    "huc_branches_to_process.$": "$.Payload.huc_branches_to_process",
                    "db_fim_table.$": "$.Payload.db_fim_table",
                    "data_bucket.$": "$.Payload.data_bucket",
                    "data_prefix.$": "$.Payload.data_prefix",
                    "reference_time.$": "$.Payload.reference_time",
                    "fim_config.$": "$.Payload.fim_config",
                    "service.$": "$.Payload.service"
                  }
                },
                "HUC Processing Map": {
                  "Type": "Map",
                  "Iterator": {
                    "StartAt": "FIM HUC Processing State Machine",
                    "States": {
                      "FIM HUC Processing State Machine": {
                        "Type": "Task",
                        "Resource": "arn:aws:states:::states:startExecution.sync:2",
                        "Parameters": {
                          "StateMachineArn": "${aws_sfn_state_machine.huc_processing_step_function.arn}",
                          "Name.$": "$.state_machine_name",
                          "Input": {
                            "huc_branches_to_process.$": "$.huc_branches_to_process",
                            "db_fim_table.$": "$.db_fim_table",
                            "data_bucket.$": "$.data_bucket",
                            "data_prefix.$": "$.data_prefix",
                            "reference_time.$": "$.reference_time",
                            "fim_config.$": "$.fim_config",
                            "service.$": "$.service.service",
                            "AWS_STEP_FUNCTIONS_STARTED_BY_EXECUTION_ID.$": "$$.Execution.Id"
                          }
                        },
                        "End": true
                      }
                    }
                  },
                  "ItemsPath": "$.huc_processing_payload.huc_branches_to_process",
                  "ResultPath": null,
                  "Next": "Postprocess SQL - FIM Config",
                  "ItemSelector": {
                    "huc_branches_to_process.$": "$$.Map.Item.Value",
                    "db_fim_table.$": "$.huc_processing_payload.db_fim_table",
                    "data_bucket.$": "$.huc_processing_payload.data_bucket",
                    "data_prefix.$": "$.huc_processing_payload.data_prefix",
                    "reference_time.$": "$.huc_processing_payload.reference_time",
                    "fim_config.$": "$.huc_processing_payload.fim_config",
                    "service.$": "$.service",
                    "state_machine_name.$": "States.Format('{}_{}_{}', $$.Execution.Name, $.fim_config, $$.Map.Item.Index)"
                  },
                  "MaxConcurrency": 4
                },
                "Postprocess SQL - FIM Config": {
                  "Type": "Task",
                  "Resource": "arn:aws:states:::lambda:invoke",
                  "Parameters": {
                    "FunctionName": "${aws_lambda_function.viz_db_postprocess_sql.arn}",
                    "Payload": {
                      "args": {
                        "map.$": "$",
                        "map_item.$": "$.fim_config",
                        "reference_time.$": "$.reference_time",
                        "sql_rename_dict.$": "$.sql_rename_dict"
                      },
                      "step": "fim_config",
                      "folder": "services"
                    }
                  },
                  "Retry": [
                    {
                      "ErrorEquals": [
                        "Lambda.ServiceException",
                        "Lambda.AWSLambdaException",
                        "Lambda.SdkClientException"
                      ],
                      "IntervalSeconds": 2,
                      "MaxAttempts": 6,
                      "BackoffRate": 2,
                      "Comment": "Lambda Service Errors"
                    }
                  ],
                  "ResultPath": null,
                  "Next": "Update EGIS Data - FIM Config"
                },
                "Update EGIS Data - FIM Config": {
                  "Type": "Task",
                  "Resource": "arn:aws:states:::lambda:invoke",
                  "Parameters": {
                    "FunctionName": "${aws_lambda_function.viz_update_egis_data.arn}",
                    "Payload": {
                      "args.$": "$",
                      "step": "update_fim_config_data"
                    }
                  },
                  "Retry": [
                    {
                      "ErrorEquals": [
                        "Lambda.ServiceException",
                        "Lambda.AWSLambdaException",
                        "Lambda.SdkClientException"
                      ],
                      "IntervalSeconds": 2,
                      "MaxAttempts": 6,
                      "BackoffRate": 2,
                      "Comment": "Lambda Service Errors"
                    }
                  ],
                  "ResultPath": null,
                  "End": true
                }
              }
            },
            "ItemsPath": "$.service.fim_configs",
            "Parameters": {
              "fim_config.$": "$$.Map.Item.Value",
              "map_item.$": "$$.Map.Item.Value",
              "job_type.$": "$.job_type",
              "service.$": "$.service",
              "reference_time.$": "$.reference_time",
              "sql_rename_dict.$": "$.sql_rename_dict"
            },
            "ResultPath": null
          },
          "Postprocess SQL - Service": {
            "Type": "Task",
            "Resource": "arn:aws:states:::lambda:invoke",
            "Parameters": {
              "FunctionName": "${aws_lambda_function.viz_db_postprocess_sql.arn}",
              "Payload": {
                "args": {
                  "map.$": "$",
                  "sql_rename_dict.$": "$.sql_rename_dict"
                },
                "step": "services",
                "folder": "services"
              }
            },
            "Retry": [
              {
                "ErrorEquals": [
                  "Lambda.ServiceException",
                  "Lambda.AWSLambdaException",
                  "Lambda.SdkClientException"
                ],
                "IntervalSeconds": 2,
                "MaxAttempts": 6,
                "BackoffRate": 2,
                "Comment": "Lambda Service Errors"
              }
            ],
            "Next": "Update EGIS Data - Service",
            "ResultPath": null
          },
          "Update EGIS Data - Service": {
            "Type": "Task",
            "Resource": "arn:aws:states:::lambda:invoke",
            "Parameters": {
              "FunctionName": "${aws_lambda_function.viz_update_egis_data.arn}",
              "Payload": {
                "args.$": "$",
                "step": "update_service_data"
              }
            },
            "Retry": [
              {
                "ErrorEquals": [
                  "Lambda.ServiceException",
                  "Lambda.AWSLambdaException",
                  "Lambda.SdkClientException"
                ],
                "IntervalSeconds": 2,
                "MaxAttempts": 6,
                "BackoffRate": 2,
                "Comment": "Lambda Service Errors"
              }
            ],
            "ResultPath": null,
            "Next": "Parallelize Summaries"
          },
          "Parallelize Summaries": {
            "Type": "Map",
            "Next": "Update EGIS Data - Unstage",
            "Iterator": {
              "StartAt": "Postprocess SQL - Summary",
              "States": {
                "Postprocess SQL - Summary": {
                  "Type": "Task",
                  "Resource": "arn:aws:states:::lambda:invoke",
                  "Parameters": {
                    "FunctionName": "${aws_lambda_function.viz_db_postprocess_sql.arn}",
                    "Payload": {
                      "args": {
                        "map.$": "$",
                        "map_item.$": "$.postprocess_summary",
                        "reference_time.$": "$.reference_time",
                        "sql_rename_dict.$": "$.sql_rename_dict"
                      },
                      "step": "summaries",
                      "folder": "summaries"
                    }
                  },
                  "Retry": [
                    {
                      "ErrorEquals": [
                        "Lambda.ServiceException",
                        "Lambda.AWSLambdaException",
                        "Lambda.SdkClientException"
                      ],
                      "IntervalSeconds": 2,
                      "MaxAttempts": 6,
                      "BackoffRate": 2,
                      "Comment": "Lambda Service Errors"
                    }
                  ],
                  "ResultPath": null,
                  "Next": "Update EGIS Data - Summary"
                },
                "Update EGIS Data - Summary": {
                  "Type": "Task",
                  "Resource": "arn:aws:states:::lambda:invoke",
                  "Parameters": {
                    "FunctionName": "${aws_lambda_function.viz_update_egis_data.arn}",
                    "Payload": {
                      "args.$": "$",
                      "step": "update_summary_data"
                    }
                  },
                  "Retry": [
                    {
                      "ErrorEquals": [
                        "Lambda.ServiceException",
                        "Lambda.AWSLambdaException",
                        "Lambda.SdkClientException"
                      ],
                      "IntervalSeconds": 2,
                      "MaxAttempts": 6,
                      "BackoffRate": 2,
                      "Comment": "Lambda Service Errors"
                    }
                  ],
                  "ResultPath": null,
                  "End": true
                }
              }
            },
            "ItemsPath": "$.service.postprocess_summary",
            "Parameters": {
              "service.$": "$.service",
              "map_item.$": "$.map_item",
              "reference_time.$": "$.reference_time",
              "job_type.$": "$.job_type",
              "sql_rename_dict.$": "$.sql_rename_dict",
              "postprocess_summary.$": "$$.Map.Item.Value"
            },
            "ResultPath": null
          },
          "Update EGIS Data - Unstage": {
            "Type": "Task",
            "Resource": "arn:aws:states:::lambda:invoke",
            "Parameters": {
              "FunctionName": "${aws_lambda_function.viz_update_egis_data.arn}",
              "Payload": {
                "args.$": "$",
                "step": "unstage"
              }
            },
            "Retry": [
              {
                "ErrorEquals": [
                  "Lambda.ServiceException",
                  "Lambda.AWSLambdaException",
                  "Lambda.SdkClientException"
                ],
                "IntervalSeconds": 2,
                "MaxAttempts": 6,
                "BackoffRate": 2,
                "Comment": "Lambda Service Errors"
              },
              {
                "ErrorEquals": [
                  "UndefinedTable"
                ],
                "BackoffRate": 2,
                "IntervalSeconds": 5,
                "MaxAttempts": 3,
                "Comment": "Stage Table Doesn't Exist"
              }
            ],
            "ResultPath": null,
            "Next": "Auto vs. Past Event Run"
          },
          "Auto vs. Past Event Run": {
            "Type": "Choice",
            "Choices": [
              {
                "Variable": "$.job_type",
                "StringEquals": "past_event",
                "Next": "Pass"
              }
            ],
            "Default": "Publish Service"
          },
          "Publish Service": {
            "Type": "Task",
            "Resource": "arn:aws:states:::lambda:invoke",
            "Parameters": {
              "FunctionName": "${aws_lambda_function.viz_publish_service.arn}",
              "Payload": {
                "args.$": "$",
                "step": "publish"
              }
            },
            "Retry": [
              {
                "ErrorEquals": [
                  "Lambda.ServiceException",
                  "Lambda.AWSLambdaException",
                  "Lambda.SdkClientException"
                ],
                "IntervalSeconds": 2,
                "MaxAttempts": 6,
                "BackoffRate": 2,
                "Comment": "Lambda Service Errors"
              }
            ],
            "Next": "Pass",
            "ResultPath": null
          },
          "Pass": {
            "Type": "Pass",
            "End": true,
            "ResultPath": null,
            "Result": {
              "ValueEnteredInForm": ""
            }
          }
        }
      },
      "Parameters": {
        "service.$": "$$.Map.Item.Value",
        "map_item.$": "$$.Map.Item.Value.postprocess_service",
        "reference_time.$": "$.pipeline_info.reference_time",
        "job_type.$": "$.pipeline_info.job_type",
        "sql_rename_dict.$": "$.pipeline_info.sql_rename_dict"
      },
      "ItemsPath": "$.pipeline_info.pipeline_services",
      "MaxConcurrency": 15,
      "ResultSelector": {
        "error.$": "$[?(@.error)]"
      },
      "End": true
    }
  },
  "TimeoutSeconds": 4500
}
  EOF
}

resource "aws_sfn_state_machine" "huc_processing_step_function" {
  name     = "huc_processing_${var.environment}"
  role_arn = var.lambda_role

  definition = <<EOF
{
  "Comment": "A description of my state machine",
  "StartAt": "FIM Data Prep - Get HUC Branch Processes",
  "States": {
    "FIM Data Prep - Get HUC Branch Processes": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${aws_lambda_function.viz_fim_data_prep.arn}",
        "Payload": {
          "args.$": "$",
          "step": "get_branch_iteration"
        }
      },
      "Retry": [
        {
          "ErrorEquals": [
            "Lambda.ServiceException",
            "Lambda.AWSLambdaException",
            "Lambda.SdkClientException",
            "Lambda.TooManyRequestsException"
          ],
          "IntervalSeconds": 2,
          "MaxAttempts": 6,
          "BackoffRate": 2
        }
      ],
      "Next": "HUC 8 Map",
      "ResultPath": "$.huc_branch_data",
      "ResultSelector": {
        "huc_branches_to_process.$": "$.Payload.huc_branches_to_process"
      }
    },
    "HUC 8 Map": {
      "Type": "Map",
      "End": true,
      "Iterator": {
        "StartAt": "HUC Processing",
        "States": {
          "HUC Processing": {
            "Type": "Task",
            "Resource": "arn:aws:states:::lambda:invoke",
            "OutputPath": "$.Payload",
            "Parameters": {
              "Payload.$": "$",
              "FunctionName": "arn:aws:lambda:${var.region}:${var.account_id}:function:${module.image_based_lambdas.fim_huc_processing}"
            },
            "End": true,
            "Retry": [
              {
                "ErrorEquals": [
                  "Lambda.ServiceException",
                  "Lambda.AWSLambdaException",
                  "Lambda.SdkClientException",
                  "Lambda.TooManyRequestsException"
                ],
                "BackoffRate": 1,
                "IntervalSeconds": 60,
                "MaxAttempts": 3,
                "Comment": "Handle insufficient capacity"
              },
              {
                "ErrorEquals": [
                  "HANDDatasetReadError"
                ],
                "BackoffRate": 1,
                "IntervalSeconds": 60,
                "MaxAttempts": 2,
                "Comment": "Issue Reading HAND Datasets"
              }
            ]
          }
        }
      },
      "MaxConcurrency": 40,
      "ItemsPath": "$.huc_branch_data.huc_branches_to_process",
      "Parameters": {
        "huc.$": "$$.Map.Item.Value.huc",
        "huc8_branch.$": "$$.Map.Item.Value.huc8_branch",
        "data_prefix.$": "$.data_prefix",
        "data_bucket.$": "$.data_bucket",
        "fim_config.$": "$.fim_config",
        "service.$": "$.service",
        "reference_time.$": "$.reference_time",
        "db_fim_table.$": "$.db_fim_table"
      }
    }
  }
}
  EOF
}

####### Step Function Failure / Time Out SNS #######
resource "aws_cloudwatch_event_rule" "viz_pipeline_step_function_failure" {
  name        = "viz_pipeline_step_function_failure_${var.environment}"
  description = "Alert when the viz step function times out or fails."

  event_pattern = <<EOF
  {
  "source": ["aws.states"],
  "detail-type": ["Step Functions Execution Status Change"],
  "detail": {
    "status": ["FAILED", "TIMED_OUT"],
    "stateMachineArn": ["${aws_sfn_state_machine.viz_pipeline_step_function.arn}"]
    }
  }
  EOF
}

resource "aws_cloudwatch_event_target" "step_function_failure_sns" {
  rule        = aws_cloudwatch_event_rule.viz_pipeline_step_function_failure.name
  target_id   = "SendToSNS"
  arn         = var.email_sns_topics["viz_lambda_errors"].arn
  input_path  = "$.detail.name"
}

########################################################################################################################################
########################################################################################################################################

output "max_flows" {
  value = aws_lambda_function.viz_max_flows
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

output "wrds_api_handler" {
  value = aws_lambda_function.viz_wrds_api_handler
}

output "viz_pipeline_step_function" {
  value = aws_sfn_state_machine.viz_pipeline_step_function
}

output "fim_huc_processing" {
  value = module.image_based_lambdas.fim_huc_processing
}

output "optimize_rasters" {
  value = module.image_based_lambdas.optimize_rasters
}

output "raster_processing" {
  value = module.image_based_lambdas.raster_processing
}