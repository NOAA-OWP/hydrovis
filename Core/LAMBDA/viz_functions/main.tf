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

variable "pandas_layer" {
  type = string
}

variable "huc_proc_combo_layer" {
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

########################################################################################################################################
########################################################################################################################################
data "aws_caller_identity" "current" {}

locals {
  egis_host      = var.environment == "prod" ? "https://maps.water.noaa.gov/portal" : var.environment == "uat" ? "https://maps-staging.water.noaa.gov/portal" : var.environment == "ti" ? "https://maps-testing.water.noaa.gov/portal" : "https://hydrovis-dev.nwc.nws.noaa.gov/portal"
  service_suffix = var.environment == "prod" ? "" : var.environment == "uat" ? "_beta" : var.environment == "ti" ? "_alpha" : "_gamma"

  max_flows_subscriptions = toset([
    "nwm_ingest_ana"
  ])

  initialize_pipeline_subscriptions = toset([
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

########################################################################################################################################
########################################################################################################################################

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
  filename         = "${path.module}/viz_wrds_api_handler.zip"
  source_code_hash = filebase64sha256("${path.module}/viz_wrds_api_handler.zip")
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

resource "aws_lambda_function" "viz_max_flows" {
  function_name = "viz_max_flows_${var.environment}"
  description   = "Lambda function to create max streamflow files for NWM data"
  memory_size   = 512
  timeout       = 900

  environment {
    variables = {
      CACHE_DAYS         = 1
      MAX_FLOWS_BUCKET   = var.max_flows_bucket
      INITIALIZE_PIPELINE_FUNCTION = aws_lambda_function.viz_initialize_pipeline.arn
    }
  }

  filename         = "${path.module}/viz_max_flows.zip"
  source_code_hash = filebase64sha256("${path.module}/viz_max_flows.zip")

  runtime = "python3.9"
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
  function_name          = resource.aws_lambda_function.viz_max_flows.function_name
  maximum_retry_attempts = 0
  destination_config {
    on_failure {
      destination = var.email_sns_topics["viz_lambda_errors"].arn
    }
  }
}

#############################
##   Initialize Pipeline   ##
#############################

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
    }
  }
  filename         = "${path.module}/viz_initialize_pipeline.zip"
  source_code_hash = filebase64sha256("${path.module}/viz_initialize_pipeline.zip")
  runtime          = "python3.9"
  handler          = "lambda_function.lambda_handler"
  role             = var.lambda_role
  layers = [
    var.psycopg2_sqlalchemy_layer,
    var.viz_lambda_shared_funcs_layer
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
  filename         = "${path.module}/viz_db_postprocess_sql.zip"
  source_code_hash = filebase64sha256("${path.module}/viz_db_postprocess_sql.zip")
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
  filename         = "${path.module}/viz_db_ingest.zip"
  source_code_hash = filebase64sha256("${path.module}/viz_db_ingest.zip")
  runtime          = "python3.9"
  handler          = "lambda_function.lambda_handler"
  role             = var.lambda_role
  layers = [
    var.psycopg2_sqlalchemy_layer,
    var.xarray_layer,
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
  filename         = "${path.module}/viz_fim_data_prep.zip"
  source_code_hash = filebase64sha256("${path.module}/viz_fim_data_prep.zip")
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
##   FIM HUC Processing    ##
#############################

resource "aws_lambda_function" "viz_fim_huc_processing" {
  function_name = "viz_fim_huc_processing_${var.environment}"
  description   = "Lambda function to process FIM for an individual huc, and load data into a specified database table."
  memory_size   = 10240

  timeout       = 900
  vpc_config {
    security_group_ids = var.db_lambda_security_groups
    subnet_ids         = var.db_lambda_subnets
  }
  environment {
    variables = {
      FIM_DATA_BUCKET             = var.fim_data_bucket
      FIM_VERSION                 = var.fim_version
      PROCESSED_OUTPUT_BUCKET     = var.fim_output_bucket
      PROCESSED_OUTPUT_PREFIX     = "processing_outputs"
      FR_FIM_BUCKET               = var.fim_data_bucket
      FR_FIM_PREFIX               = "fim_${replace(var.fim_version, ".", "_")}_fr_c"
      MS_FIM_BUCKET               = var.fim_data_bucket
      MS_FIM_PREFIX               = "fim_${replace(var.fim_version, ".", "_")}_ms_c"
      VIZ_DB_DATABASE             = var.viz_db_name
      VIZ_DB_HOST                 = var.viz_db_host
      VIZ_DB_USERNAME             = jsondecode(var.viz_db_user_secret_string)["username"]
      VIZ_DB_PASSWORD             = jsondecode(var.viz_db_user_secret_string)["password"]
    }
  }
  filename         = "${path.module}/viz_fim_huc_processing.zip"
  source_code_hash = filebase64sha256("${path.module}/viz_fim_huc_processing.zip")
  runtime          = "python3.9"
  handler          = "lambda_function.lambda_handler"
  role             = var.lambda_role
  layers = [
    var.huc_proc_combo_layer,
    var.es_logging_layer,
    var.viz_lambda_shared_funcs_layer
  ]
  tags = {
    "Name" = "viz_fim_huc_processing_${var.environment}"
  }
  ephemeral_storage {
    size = 2048
  }
}

resource "aws_lambda_function_event_invoke_config" "viz_fim_huc_processing_destinations" {
  function_name          = resource.aws_lambda_function.viz_fim_huc_processing.function_name
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

resource "aws_lambda_function" "viz_update_egis_data" {
  function_name = "viz_update_egis_data_${var.environment}"
  description   = "Lambda function to copy a postprocesses service table into the egis postgreql database, as well as cache data in the viz database."
  memory_size   = 4200
  timeout       = 900
  vpc_config {
    security_group_ids = var.db_lambda_security_groups
    subnet_ids         = var.db_lambda_subnets
  }
  environment {
    variables = {
      EGIS_DB_DATABASE    = var.egis_db_name
      EGIS_DB_HOST        = var.egis_db_host
      EGIS_DB_USERNAME    = jsondecode(var.egis_db_secret_string)["username"]
      EGIS_DB_PASSWORD    = jsondecode(var.egis_db_secret_string)["password"]
      VIZ_DB_DATABASE     = var.viz_db_name
      VIZ_DB_HOST         = var.viz_db_host
      VIZ_DB_USERNAME     = jsondecode(var.viz_db_user_secret_string)["username"]
      VIZ_DB_PASSWORD     = jsondecode(var.viz_db_user_secret_string)["password"]
    }
  }
  filename         = "${path.module}/viz_update_egis_data.zip"
  source_code_hash = filebase64sha256("${path.module}/viz_update_egis_data.zip")
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
  ephemeral_storage {
    size = 2048
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

resource "aws_lambda_function" "viz_publish_service" {
  function_name = "viz_publish_service_${var.environment}"
  description   = "Lambda function to check and publish (if needed) an egis service based on a SD file in S3."
  memory_size   = 512
  timeout       = 180
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
  filename         = "${path.module}/viz_publish_service.zip"
  source_code_hash = filebase64sha256("${path.module}/viz_publish_service.zip")
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
  "StartAt": "Choice",
  "States": {
    "Choice": {
      "Type": "Choice",
      "Choices": [
        {
          "Or": [
            {
              "Variable": "$.pipeline_info.data_type",
              "StringEquals": "forcing"
            },
            {
              "Variable": "$.pipeline_info.data_type",
              "StringEquals": "land"
            }
          ],
          "Comment": "Forcing/Land Inputs",
          "Next": "Services Processing"
        }
      ],
      "Default": "Database Ingest Groups"
    },
    "Database Ingest Groups": {
      "Type": "Map",
      "Next": "Max Flows Processing",
      "Iterator": {
        "StartAt": "Postprocess SQL - Ingest Prep",
        "States": {
          "Postprocess SQL - Ingest Prep": {
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
                "BackoffRate": 2
              }
            ],
            "Next": "Database Ingest Files",
            "ResultPath": null
          },
          "Database Ingest Files": {
            "Type": "Map",
            "Iterator": {
              "StartAt": "DB Ingest",
              "States": {
                "DB Ingest": {
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
                      "IntervalSeconds": 60,
                      "MaxAttempts": 15,
                      "Comment": "Missing S3 File"
                    }
                  ]
                }
              }
            },
            "InputPath": "$.map.ingest_datasets",
            "ResultPath": null,
            "Next": "Postprocess SQL - Ingest Finish"
          },
          "Postprocess SQL - Ingest Finish": {
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
                "BackoffRate": 2
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
                "BackoffRate": 2
              }
            ],
            "End": true
          }
        }
      },
      "ResultPath": null,
      "ItemsPath": "$.pipeline_info.max_flows",
      "Parameters": {
        "map_item.$": "$$.Map.Item.Value.max_flows",
        "max_flows.$": "$$.Map.Item.Value",
        "reference_time.$": "$.pipeline_info.reference_time",
        "sql_rename_dict.$": "$.pipeline_info.sql_rename_dict"
      },
      "MaxConcurrency": 5
    },
    "Services Processing": {
      "Type": "Map",
      "Iterator": {
        "StartAt": "Vector vs Raster",
        "States": {
          "Vector vs Raster": {
            "Type": "Choice",
            "Choices": [
              {
                "Variable": "$.service.egis_server",
                "StringEquals": "image",
                "Next": "Raster Processing",
                "Comment": "Raster Processing"
              }
            ],
            "Default": "FIM vs Non-FIM Services"
          },
          "FIM vs Non-FIM Services": {
            "Type": "Choice",
            "Choices": [
              {
                "Variable": "$.service.service_type ",
                "StringEquals": "fim",
                "Comment": "FIM Processing",
                "Next": "FIM Processing"
              }
            ],
            "Default": "Postprocess SQL - Service"
          },
          "Raster Processing": {
            "Type": "Task",
            "Resource": "arn:aws:states:::lambda:invoke",
            "Parameters": {
              "Payload.$": "$",
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
                "BackoffRate": 2
              }
            ],
            "Next": "Update EGIS Data - Service",
            "ResultPath": "$.raster_result",
            "ResultSelector": {
              "output_rasters.$": "$.Payload"
            }
          },
          "FIM Processing": {
            "Type": "Map",
            "Next": "Postprocess SQL - Service",
            "Iterator": {
              "StartAt": "FIM Data Preparation",
              "States": {
                "FIM Data Preparation": {
                  "Type": "Task",
                  "Resource": "arn:aws:states:::lambda:invoke",
                  "OutputPath": "$.Payload",
                  "Parameters": {
                    "FunctionName": "${aws_lambda_function.viz_fim_data_prep.arn}",
                    "Payload": {
                      "args.$": "$",
                      "step": "fim_prep"
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
                      "BackoffRate": 2
                    }
                  ],
                  "Next": "HUC Processing Map"
                },
                "HUC Processing Map": {
                  "Type": "Map",
                  "Iterator": {
                    "StartAt": "FIM Processing by HUC",
                    "States": {
                      "FIM Processing by HUC": {
                        "Type": "Task",
                        "Resource": "arn:aws:states:::lambda:invoke",
                        "OutputPath": "$.Payload",
                        "Parameters": {
                          "FunctionName": "${aws_lambda_function.viz_fim_huc_processing.arn}",
                          "Payload": {
                            "args.$": "$",
                            "step": "fim_processing"
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
                            "BackoffRate": 2
                          }
                        ],
                        "End": true
                      }
                    }
                  },
                  "ItemsPath": "$.taskList",
                  "ResultPath": null,
                  "MaxConcurrency": 200,
                  "End": true,
                  "InputPath": "$.body"
                }
              }
            },
            "ItemsPath": "$.service.fim_configs",
            "Parameters": {
              "fim_config.$": "$$.Map.Item.Value",
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
                "BackoffRate": 2
              }
            ],
            "Next": "Update EGIS Data - Service",
            "ResultPath": null
          },
          "Update EGIS Data - Service": {
            "Type": "Task",
            "Resource": "arn:aws:states:::lambda:invoke",
            "Parameters": {
              "FunctionName": "arn:aws:lambda:us-east-1:526904826677:function:viz_update_egis_data_dev",
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
                "BackoffRate": 2
              }
            ],
            "ResultPath": null,
            "Next": "Summary vs. Non-Summary Services"
          },
          "Summary vs. Non-Summary Services": {
            "Type": "Choice",
            "Choices": [
              {
                "Variable": "$.service.postprocess_summary",
                "IsNull": true,
                "Next": "Auto vs. Past Event Run"
              }
            ],
            "Default": "Postprocess SQL - Summary"
          },
          "Auto vs. Past Event Run": {
            "Type": "Choice",
            "Choices": [
              {
                "Variable": "$.job_type",
                "StringEquals": "past_event",
                "Next": "Success"
              }
            ],
            "Default": "Publish Service"
          },
          "Postprocess SQL - Summary": {
            "Type": "Task",
            "Resource": "arn:aws:states:::lambda:invoke",
            "Parameters": {
              "FunctionName": "${aws_lambda_function.viz_db_postprocess_sql.arn}",
              "Payload": {
                "args": {
                  "map.$": "$",
                  "map_item.$": "$.service.postprocess_summary",
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
                "BackoffRate": 2
              }
            ],
            "Next": "Update EGIS Data - Summary",
            "ResultPath": null
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
                "BackoffRate": 2
              }
            ],
            "ResultPath": null,
            "Next": "Auto vs. Past Event Run"
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
                "BackoffRate": 2
              }
            ],
            "Next": "Success"
          },
          "Success": {
            "Type": "Succeed"
          }
        }
      },
      "ResultPath": null,
      "Parameters": {
        "service.$": "$$.Map.Item.Value",
        "map_item.$": "$$.Map.Item.Value.postprocess_service",
        "reference_time.$": "$.pipeline_info.reference_time",
        "job_type.$": "$.pipeline_info.job_type",
        "sql_rename_dict.$": "$.pipeline_info.sql_rename_dict"
      },
      "ItemsPath": "$.pipeline_info.pipeline_services",
      "End": true,
      "MaxConcurrency": 15
    }
  },
  "TimeoutSeconds": 3600
}
  EOF
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

output "fim_huc_processing" {
  value = aws_lambda_function.viz_fim_huc_processing
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