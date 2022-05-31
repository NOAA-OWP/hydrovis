variable "environment" {
  type = string
}

variable "account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "es_endpoint" {
  type = string
}

variable "es_sgs" {
  type = list(string)
}

variable "data_subnets" {
  type = list(string)
}

locals {
  buckets_and_parameters = {
    "hml" = {
      # TODO: Import this name from s3 module
      bucket_name         = "hydrovis-${var.environment}-hml-${var.region}"
      comparison_operator = "LessThanLowerThreshold"
    }
    "nwm" = {
      # TODO: Import this name from s3 module
      bucket_name         = "hydrovis-${var.environment}-nwm-${var.region}"
      comparison_operator = "LessThanLowerThreshold"
    }
    "pcpanl" = {
      # TODO: Import this name from s3 module
      bucket_name         = "hydrovis-${var.environment}-pcpanl-${var.region}"
      comparison_operator = "LessThanLowerThreshold"
    }
  }
}

module "bucket" {
  source   = "./bucket"
  for_each = local.buckets_and_parameters

  environment = var.environment
  account_id  = var.account_id

  name                 = each.key
  bucket_name          = each.value["bucket_name"]
  comparison_operator  = each.value["comparison_operator"]
}

data "aws_iam_role" "LambdaforElasticsearch" {
  name = "LambdaforElasticsearch"
}

data "archive_file" "lambda_code" {
  type = "zip"

  source {
    content  = templatefile("${path.module}/lambda_code/index.js.tftpl", {
      es_endpoint = var.es_endpoint
      region      = var.region
    })
    filename = "index.js"
  }

  output_path = "${path.module}/lambda_code_${var.environment}.zip"
}

resource "aws_lambda_function" "CWS3AlertsToMonitoring" {
  function_name = "CWS3AlertsToMonitoring"
  description   = "CloudWatch S3 Alerts to Amazon OpenSearch"
  memory_size   = 128
  timeout       = 300

  filename         = data.archive_file.lambda_code.output_path
  source_code_hash = data.archive_file.lambda_code.output_base64sha256

  runtime = "nodejs12.x"
  handler = "index.handler"

  role = data.aws_iam_role.LambdaforElasticsearch.arn
  vpc_config {
    subnet_ids         = var.data_subnets
    security_group_ids = var.es_sgs
  }
}

resource "aws_sns_topic_subscription" "CWS3AlertsToMonitoring_subscription" {
  for_each = local.buckets_and_parameters

  topic_arn = module.bucket[each.key].sns.arn
  protocol  = "lambda"
  endpoint  = resource.aws_lambda_function.CWS3AlertsToMonitoring.arn
}

resource "aws_lambda_permission" "CWS3AlertsToMonitoring_permissions" {
  for_each = local.buckets_and_parameters

  action        = "lambda:InvokeFunction"
  function_name = resource.aws_lambda_function.CWS3AlertsToMonitoring.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = module.bucket[each.key].sns.arn
}