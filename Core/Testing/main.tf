terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      configuration_aliases = [ aws.sns, aws.no_tags]
    }
  }
}

variable "environment" {
  type = string
}

variable "s3_module" {
  type = any
}

variable "lambda_module" {
  type = any
}

variable "step_function_module" {
  type = any
}

locals {
  test_bucket = var.s3_module.buckets["deployment"].bucket
  init_pipeline_lambda = var.lambda_module.initialize_pipeline
}

resource "aws_cloudwatch_event_rule" "detect_test_files" {
  name                = "hv-vpp-${var.environment}-detect-test-files"
  description         = "Detects when a new test file has been created"
  event_pattern       = <<EOF
  {
    "source": ["aws.s3"],
    "detail-type": ["Object Created"],
    "detail": {
      "bucket": {
        "name": ["${local.test_bucket}"]
      },
      "object": {
        "key": [{
          "prefix": "common/data/model/com/nwm/prod/nwm."
        }]
      }
    }
  }
  EOF
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_initialize_pipeline" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = local.init_pipeline_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.detect_test_files.arn
}

resource "aws_cloudwatch_event_target" "trigger_pipeline_test_run" {
  rule      = aws_cloudwatch_event_rule.detect_test_files.name
  target_id = local.init_pipeline_lambda.function_name
  arn       = local.init_pipeline_lambda.arn
  input_transformer {
    input_paths = {
      "s3_bucket": "$.detail.bucket.name",
      "s3_key": "$.detail.object.key"
    }
    input_template = <<EOF
    {
      "Records": [
        {
          "Sns": {
            "TopicArn": "N/A",
            "Message": "{\"Records\": [{\"s3\": {\"bucket\": {\"name\": \"<s3_bucket>\"}, \"object\": {\"key\": \"<s3_key>\"}}}]}"
          }
        }
      ]
    }
    EOF
  }
}

##################################
###### KICK OFF TESTS IN TI ######
##################################
data "aws_s3_objects" "test_nwm_outputs" {
  bucket        = local.test_bucket
  prefix        = "test_nwm_outputs/"
  max_keys      = 2000
}

resource "aws_s3_object_copy" "test" {
  provider = aws.no_tags
  depends_on  = [var.s3_module, var.lambda_module, var.step_function_module, aws_cloudwatch_event_target.trigger_pipeline_test_run]
  count       = length(data.aws_s3_objects.test_nwm_outputs.keys)
  bucket      = local.test_bucket
  source      = join("/", [local.test_bucket, element(data.aws_s3_objects.test_nwm_outputs.keys, count.index)])
  key         = replace(element(data.aws_s3_objects.test_nwm_outputs.keys, count.index), "test_nwm_outputs", formatdate("'common/data/model/com/nwm/prod/nwm.'YYYYMMDD", timestamp()))
}
