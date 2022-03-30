variable "account_id" {
  type = string
}

variable "fim_bucket_name" {
  type = string
}

variable "lambda_trigger_functions" {
  type = set(string)
}

resource "local_file" "lambda_code_index" {
  content  = templatefile("${path.module}/lambda_code/index.js.tftpl", {
    es_endpoint = aws_elasticsearch_domain.es.endpoint
  })
  filename = "${path.module}/lambda_code/index.js"
}

data "archive_file" "lambda_code" {
  type = "zip"

  source_dir  = "${path.module}/lambda_code"
  output_path = "${path.module}/lambda_code.zip"
}

resource "aws_iam_role" "LambdaforElasticsearch" {
  name = "LambdaforElasticsearch"

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

resource "aws_iam_role_policy" "LambdaforElasticsearch" {
  name   = "LambdaforElasticsearch"
  role   = aws_iam_role.LambdaforElasticsearch.id
  policy = templatefile("${path.module}/LambdaforElasticsearch.json.tftpl", {
    account_id = var.account_id
    region     = var.region
  })
}

resource "aws_iam_role_policy_attachment" "AWSLambdaVPCAccessExecutionRole" {
  role       = aws_iam_role.LambdaforElasticsearch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_lambda_function" "CWLogsToElasticsearch" {
  function_name = "CWLogsToElasticsearch"
  description   = "CloudWatch Logs to Amazon ES streaming"
  memory_size   = 128
  timeout       = 300

  filename         = data.archive_file.lambda_code.output_path
  source_code_hash = data.archive_file.lambda_code.output_base64sha256

  runtime = "nodejs12.x"
  handler = "index.handler"

  role = aws_iam_role.LambdaforElasticsearch.arn
  vpc_config {
    subnet_ids         = var.data_subnets
    security_group_ids = var.es_sgs
  }
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  for_each      = var.lambda_trigger_functions
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.CWLogsToElasticsearch.function_name
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
  destination_arn = aws_lambda_function.CWLogsToElasticsearch.arn
  depends_on      = [aws_lambda_permission.allow_cloudwatch, aws_cloudwatch_log_group.loggroup]
}
