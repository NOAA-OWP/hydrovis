variable "environment" {
  type = string
}

variable "account_id" {
  type = string
}

variable "name" {
  type = string
}

variable "bucket_name" {
  type = string
}

variable "comparison_operator" {
  type = string
}

resource "aws_sns_topic" "alert_sns" {
  name         = "${var.environment}_S3_${var.name}_anomaly_detection"
  display_name = "${var.environment}_S3_${var.name}_anomaly_detection"
  tags = {
    Name = "${var.environment}_S3_${var.name}_anomaly_detection"
  }
}

resource "aws_cloudwatch_metric_alarm" "s3_bucket_anomoly_detection" {
  alarm_actions             = [aws_sns_topic.alert_sns.id]
  ok_actions                = [aws_sns_topic.alert_sns.id]
  alarm_name                = "${var.environment}_S3_${var.name}_anomaly_detection"
  comparison_operator       = var.comparison_operator
  datapoints_to_alarm       = 1
  evaluation_periods        = 1
  threshold_metric_id       = "ad1"

  metric_query {
    id          = "m1"
    return_data = true

    metric {
      dimensions  = {
        "BucketName"  = var.bucket_name
        "StorageType" = "AllStorageTypes"
      }
      metric_name = "NumberOfObjects"
      namespace   = "AWS/S3"
      period      = 86400
      stat        = "Average"
    }
  }
  metric_query {
    expression  = "ANOMALY_DETECTION_BAND(m1, 2)"
    id          = "ad1"
    label       = "NumberOfObjects (expected)"
    return_data = true
  }
}

output "sns" {
  value = aws_sns_topic.alert_sns
}
