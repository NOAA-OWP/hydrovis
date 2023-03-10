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

variable "master_user_credentials_secret_string" {
  type = string
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
      admin_username = jsondecode(var.master_user_credentials_secret_string)["username"]
      admin_password = jsondecode(var.master_user_credentials_secret_string)["password"]
    })
    filename = "index.js"
  }

  output_path = "${path.module}/lambda_code_${var.environment}.zip"
}

resource "aws_lambda_function" "opensearch_s3_log_ingester" {
  function_name = "opensearch_s3_log_ingester_${var.environment}"
  description   = "S3 Logs to Amazon OpenSearch"
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

resource "aws_sns_topic_subscription" "opensearch_s3_log_ingester_subscription" {
  for_each = var.buckets_and_parameters

  topic_arn = module.bucket[each.key].sns.arn
  protocol  = "lambda"
  endpoint  = resource.aws_lambda_function.opensearch_s3_log_ingester.arn
}

resource "aws_lambda_permission" "opensearch_s3_log_ingester_permissions" {
  for_each = var.buckets_and_parameters

  action        = "lambda:InvokeFunction"
  function_name = resource.aws_lambda_function.opensearch_s3_log_ingester.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = module.bucket[each.key].sns.arn
}