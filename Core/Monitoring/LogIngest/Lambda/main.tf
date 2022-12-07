variable "environment" {
  type = string
}

variable "account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "opensearch_security_group_ids" {
  type = list(string)
}

variable "data_subnet_ids" {
  type = list(string)
}

variable "lambda_trigger_functions" {
  type = set(string)
}

variable "opensearch_domain_arn" {
  type = string
}

variable "opensearch_domain_endpoint" {
  type = string
}

variable "master_user_credentials_secret_string" {
  type = string
}


data "archive_file" "lambda_code" {
  type = "zip"

  source {
    content  = templatefile("${path.module}/index.js.tftpl", {
      os_endpoint    = var.opensearch_domain_endpoint
      admin_username = jsondecode(var.master_user_credentials_secret_string)["username"]
      admin_password = jsondecode(var.master_user_credentials_secret_string)["password"]
    })
    filename = "index.js"
  }

  source {
    content  = file("${path.module}/viz_js.js")
    filename = "viz_js.js"
  }

  output_path = "${path.module}/lambda_code_${var.environment}.zip"
}

resource "aws_iam_role" "hydrovis-opensearch-lambda" {
  name = "hydrovis-opensearch-lambda"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "lambda.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "hydrovis-opensearch-lambda" {
  name   = "hydrovis-opensearch-lambda"
  role   = aws_iam_role.hydrovis-opensearch-lambda.id
  policy = templatefile("${path.module}/hydrovis-opensearch-lambda.json.tftpl", {
    account_id            = var.account_id
    region                = var.region
    opensearch_domain_arn = var.opensearch_domain_arn
  })
}

resource "aws_iam_role_policy_attachment" "AWSLambdaVPCAccessExecutionRole" {
  role       = aws_iam_role.hydrovis-opensearch-lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_lambda_function" "opensearch_lambda_log_ingester" {
  function_name = "opensearch_lambda_log_ingester_${var.environment}"
  description   = "Lambda Logs to Amazon OpenSearch"
  memory_size   = 128
  timeout       = 300

  filename         = data.archive_file.lambda_code.output_path
  source_code_hash = data.archive_file.lambda_code.output_base64sha256

  runtime = "nodejs16.x"
  handler = "index.handler"

  role = aws_iam_role.hydrovis-opensearch-lambda.arn
  vpc_config {
    subnet_ids         = var.data_subnet_ids
    security_group_ids = var.opensearch_security_group_ids
  }
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  for_each      = var.lambda_trigger_functions
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.opensearch_lambda_log_ingester.function_name
  principal     = "logs.${var.region}.amazonaws.com"
  source_arn    = "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/${each.key}:*"
}

resource "aws_cloudwatch_log_group" "loggroup" {
  for_each = var.lambda_trigger_functions
  name     = "/aws/lambda/${each.key}"
}

resource "aws_cloudwatch_log_subscription_filter" "logfilter" {
  for_each        = var.lambda_trigger_functions
  name            = "${each.key}_logfilter"
  log_group_name  = "/aws/lambda/${each.key}"
  filter_pattern  = "?ELASTICSEARCH ?ERROR ?REPORT"
  destination_arn = aws_lambda_function.opensearch_lambda_log_ingester.arn
  depends_on      = [aws_lambda_permission.allow_cloudwatch, aws_cloudwatch_log_group.loggroup]
}

output "role_arn" {
  value = aws_iam_role.hydrovis-opensearch-lambda.arn
}