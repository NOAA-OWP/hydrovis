variable "environment" {
  type = string
}

variable "account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "data_subnet_ids" {
  type = list(string)
}

variable "opensearch_security_group_ids" {
  type = list(string)
}

variable "opensearch_domain_endpoint" {
  type = string
}

variable "lambda_role_arn" {
  type = string
}

variable "buckets_and_parameters" {
  type = map(map(string))
}


module "bucket" {
  source   = "./bucket"
  for_each = var.buckets_and_parameters

  environment = var.environment
  account_id  = var.account_id

  name                 = each.key
  bucket_name          = each.value["bucket_name"]
  comparison_operator  = each.value["comparison_operator"]
}

data "archive_file" "lambda_code" {
  type = "zip"

  source {
    content  = templatefile("${path.module}/index.js.tftpl", {
      os_endpoint = var.opensearch_domain_endpoint
      region      = var.region
    })
    filename = "index.js"
  }

  output_path = "${path.module}/lambda_code_${var.environment}.zip"
}

resource "aws_lambda_function" "CWS3AlertsToOpenSearch" {
  function_name = "CWS3AlertsToOpenSearch"
  description   = "CloudWatch S3 Alerts to Amazon OpenSearch"
  memory_size   = 128
  timeout       = 300

  filename         = data.archive_file.lambda_code.output_path
  source_code_hash = data.archive_file.lambda_code.output_base64sha256

  runtime = "nodejs16.x"
  handler = "index.handler"

  role = var.lambda_role_arn
  vpc_config {
    subnet_ids         = var.data_subnet_ids
    security_group_ids = var.opensearch_security_group_ids
  }
}

resource "aws_sns_topic_subscription" "CWS3AlertsToOpenSearch_subscription" {
  for_each = var.buckets_and_parameters

  topic_arn = module.bucket[each.key].sns.arn
  protocol  = "lambda"
  endpoint  = resource.aws_lambda_function.CWS3AlertsToOpenSearch.arn
}

resource "aws_lambda_permission" "CWS3AlertsToOpenSearch_permissions" {
  for_each = var.buckets_and_parameters

  action        = "lambda:InvokeFunction"
  function_name = resource.aws_lambda_function.CWS3AlertsToOpenSearch.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = module.bucket[each.key].sns.arn
}