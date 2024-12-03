terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      configuration_aliases = [ aws.sns, aws.no_tags]
    }
  }
}

variable "environment" {
  description = "Hydrovis environment"
  type        = string
}

variable "region" {
  type = string
}

variable "deployment_bucket" {
  type = string
}

variable "lambda_role" {
  type = string
}

variable "psycopg2_sqlalchemy_layer" {
  type = string
}

variable "pika_layer" {
  type = string
}

variable "rfc_fcst_user_secret_string" {
  type = string
}

variable "mq_ingest_id" {
  type = string
}

variable "db_ingest_name" {
  type = string
}

variable "db_ingest_host" {
  type = string
}

variable "mq_ingest_port" {
  type = string
}

variable "db_ingest_port" {
  type = string
}

# variable "primary_hml_bucket_name" {
#   type        = string
#   description = "Primary S3 bucket that is used for the Lambda event notification"
# }

# variable "primary_hml_bucket_arn" {
#   type        = string
#   description = "Primary S3 bucket that is used for the Lambda event notification"
# }

variable "backup_hml_bucket_name" {
  type        = string
  description = "Primary S3 bucket that is used for the Lambda event notification"
}

variable "backup_hml_bucket_arn" {
  type        = string
  description = "Primary S3 bucket that is used for the Lambda event notification"
}

variable "lambda_subnet_ids" {
  type = list(string)
}

variable "lambda_security_group_ids" {
  type = list(string)
}

variable "nws_shared_account_hml_sns" {
  type = string
}


locals {
  mq_vhost = {
    "dev" : "development",
    "development" : "development",
    "ti" : "testing_integration",
    "uat" : "user_acceptance_testing",
    "prod" : "production",
    "production" : "production",
  }
}

###########################
## HML Reciever Function ##
###########################

resource "aws_lambda_function" "hml_reciever" {
  function_name = "hv-vpp-${var.environment}-hml-receiver"
  description   = "HML receiver function that updates PostgreSQL and RabbitMQ about incoming file"
  memory_size   = 128
  timeout       = 300

  environment {
    variables = {
      OSECRETKEY   = ""
      RVIRTUALHOST = local.mq_vhost[var.environment]
      DBHOST       = var.db_ingest_host
      FDIRECTORY   = ""
      RUSERNAME    = jsondecode(var.rfc_fcst_user_secret_string)["username"]
      DBUSER       = jsondecode(var.rfc_fcst_user_secret_string)["username"]
      OACCESSKEY   = ""
      RPASSWORD    = jsondecode(var.rfc_fcst_user_secret_string)["password"]
      FHOST        = ""
      OPORT        = ""
      RPORT        = var.mq_ingest_port
      RSCHEME      = "amqps"
      OHOST        = ""
      DBPASSWORD   = jsondecode(var.rfc_fcst_user_secret_string)["password"]
      OBUCKET      = ""
      RHOST        = "${var.mq_ingest_id}.mq.${var.region}.amazonaws.com"
      DB           = var.db_ingest_name
      DBPORT       = var.db_ingest_port
      LOG_FORMAT   = "[ELASTICSEARCH %%(levelname)s]:  %%(asctime)s - %%(message)s"
    }
  }

  filename         = "${path.module}/HML_receiver_lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/HML_receiver_lambda.zip")

  runtime = "python3.9"
  handler = "hml_receiver.lambda_function"

  role = var.lambda_role

  layers = [
    var.psycopg2_sqlalchemy_layer,
    var.pika_layer
  ]

  vpc_config {
    subnet_ids         = var.lambda_subnet_ids
    security_group_ids = var.lambda_security_group_ids
  }

  tags = {
    "Name" = "hv-vpp-${var.environment}-hml-receiver"
  }
}

################################
## Shared Account SNS Trigger ##
################################

resource "aws_sns_topic_subscription" "shared_account_hml_sns_trigger" {
  provider  = aws.sns
  topic_arn = var.nws_shared_account_hml_sns
  protocol  = "lambda"
  endpoint  = resource.aws_lambda_function.hml_reciever.arn
}

resource "aws_lambda_permission" "shared_account_hml_sns_permission" {
  action        = "lambda:InvokeFunction"
  function_name = resource.aws_lambda_function.hml_reciever.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.nws_shared_account_hml_sns
}

############################
## S3 Event Notifications ##
############################

resource "aws_lambda_permission" "backup_bucket_permissions" {
  action        = "lambda:InvokeFunction"
  function_name = resource.aws_lambda_function.hml_reciever.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = var.backup_hml_bucket_arn
}

resource "aws_s3_bucket_notification" "backup_bucket_notification" {
  bucket = var.backup_hml_bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.hml_reciever.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.backup_bucket_permissions]
}

#############
## Outputs ##
#############

output "hml_reciever" {
  value = aws_lambda_function.hml_reciever
}
