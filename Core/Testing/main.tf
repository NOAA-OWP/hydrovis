variable "environment" {
  type = string
}

variable "test_data_bucket" {
  type = string
}

variable "viz_initialize_pipeline_arn" {
  type = string
}

variable "step_function_arn" {
  type = string
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
        "name": ["${var.test_data_bucket}"]
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

resource "aws_cloudwatch_event_target" "trigger_pipeline_test_run" {
  rule      = aws_cloudwatch_event_rule.detect_test_files.name
  target_id = "initialize_pipeline"
  arn       = var.viz_initialize_pipeline_arn
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
            "Message": "{\"Records\": [{\"s3\": {\"bucket\": {\"name\": \"<s3_bucket>\"}, \"object\": {\"key\": \"<s3_key>\"}}}]}"
          }
        }
      ]
    }
    EOF
  }
}

# Kick off tests in TI
data "aws_s3_objects" "test_nwm_outputs" {
  bucket        = var.test_data_bucket
  prefix        = "test_nwm_outputs/"
  max_keys      = 2000
}

resource "aws_s3_object_copy" "test" {
  count       = length(data.aws_s3_objects.test_nwm_outputs.keys)
  bucket      = var.test_data_bucket
  source      = join("/", [var.test_data_bucket, element(data.aws_s3_objects.test_nwm_outputs.keys, count.index)])
  key         = replace(element(data.aws_s3_objects.test_nwm_outputs.keys, count.index), "test_nwm_outputs", formatdate("'common/data/model/com/nwm/prod/nwm.'YYYYDDMM", timestamp()))
  depends_on  = [var.step_function_arn]
}
