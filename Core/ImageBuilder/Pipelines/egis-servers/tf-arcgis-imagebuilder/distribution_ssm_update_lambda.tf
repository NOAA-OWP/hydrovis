data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_iam_policy_document" "lambda_logging" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:*:*:*"
    ]
  }
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "start_automation_execution_policy" {
  statement {
    effect = "Allow"
    actions = [
      "ssm:PutParameter",
      "ssm:AddTagsToResource",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:ListTagsForResource"
    ]
    resources = flatten (
      [
        for region in var.destination_aws_regions : [
          "arn:${data.aws_partition.current.partition}:ssm:${region}:${data.aws_caller_identity.current.account_id}:parameter",
          "arn:${data.aws_partition.current.partition}:ssm:${region}:${data.aws_caller_identity.current.account_id}:parameter/*"
        ]
      ]
    )
  }
  statement {
    effect = "Allow"
    actions = [
      "sns:Publish"
    ]
    resources = [
      aws_sns_topic.esri_image_builder_sns_topic.id
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:*:*:*"
    ]
  }
}

resource "aws_cloudwatch_log_group" "start_automation_execution_handler_log_group" {
  name              = join("/", ["/aws/lambda", aws_lambda_function.ami_ssm_lambda_function.function_name])
  retention_in_days = var.lambda_cloud_watch_log_group_retention_in_days
}

resource "aws_iam_policy" "lambda_logging" {
  name        = "lambda_logging"
  path        = "/"
  description = "IAM policy for logging from a lambda"
  policy      = data.aws_iam_policy_document.lambda_logging.json
}

resource "aws_iam_role" "start_automation_execution_handler_lambda_role" {
  name = "AutomationExecutionHandlerFunctionRole"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_policy" "start_automation_execution_handler_lambda_policy" {
  name        = "PolicyExecutionHandler"
  description = "Automation Execution Handler policy"
  path        = "/"
  policy      = data.aws_iam_policy_document.start_automation_execution_policy.json
}

resource "aws_iam_role_policy_attachment" "start_automation_execution_handler_lambda_role_attachment" {
  role       = aws_iam_role.start_automation_execution_handler_lambda_role.name
  policy_arn = aws_iam_policy.start_automation_execution_handler_lambda_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role = aws_iam_role.start_automation_execution_handler_lambda_role.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}

data "archive_file" "python_lambda_package" {
  type        = "zip"
  source_file = "${path.module}/scripts/lambda_function.py"
  output_path = "${path.module}/scripts/lambda_function_payload.zip"
}

resource "aws_lambda_function" "ami_ssm_lambda_function" {
  filename         = "${path.module}/scripts/lambda_function_payload.zip"
  function_name    = "lambda_ami_distribution_function"
  description      = "Lambda function that will update SSM parameters with the old and new AMI IDs"
  source_code_hash = data.archive_file.python_lambda_package.output_base64sha256
  role             = aws_iam_role.start_automation_execution_handler_lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  memory_size = 256
  timeout = 300
  
  environment {
    variables = {
      ssm_prefix = "${var.aws_ssm_egis_amiid_store}"
    }
  }
}

resource "aws_lambda_permission" "lambda_log_group_permission" {
  statement_id  = "LambdaPerms4Logs"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ami_ssm_lambda_function.arn
  principal     = "logs.amazonaws.com"
  source_arn    = aws_cloudwatch_log_group.start_automation_execution_handler_log_group.arn
}

resource "aws_lambda_permission" "lambda_permission_for_sns" {
  statement_id  = "LambdaPerms4SNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ami_ssm_lambda_function.arn
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.esri_image_builder_sns_topic.id
}

resource "aws_sns_topic" "esri_image_builder_sns_topic" {
  name = "esri-image-builder-sns-topic"
}

resource "aws_sns_topic_subscription" "esri_image_builder_sns_target" {
  topic_arn = aws_sns_topic.esri_image_builder_sns_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.ami_ssm_lambda_function.arn
}
