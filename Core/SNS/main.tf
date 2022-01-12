variable "environment" {
  description = "Hydrovis environment"
  type        = string
}

variable "nwm_data_bucket" {
  description = "S3 bucket for NWM data"
  type        = string
}

variable "nwm_max_flows_data_bucket" {
  description = "S3 bucket for max flows data"
  type        = string
}


variable "rnr_max_flows_data_bucket" {
  description = "S3 bucket for rnr max flows data"
  type        = string
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {

  sns_topics = {
    nwm_ingest_ana       = var.nwm_data_bucket
    nwm_ingest_ana_hi    = var.nwm_data_bucket
    nwm_ingest_ana_prvi  = var.nwm_data_bucket
    nwm_ingest_srf       = var.nwm_data_bucket
    nwm_ingest_srf_hi    = var.nwm_data_bucket
    nwm_ingest_srf_prvi  = var.nwm_data_bucket
    nwm_ingest_mrf_3day  = var.nwm_data_bucket
    nwm_ingest_mrf_5day  = var.nwm_data_bucket
    nwm_ingest_mrf_10day = var.nwm_data_bucket
    rnr_max_flows        = var.rnr_max_flows_data_bucket
    nwm_max_flows        = var.nwm_max_flows_data_bucket
  }
}

################
## SNS Topics ##
################

resource "aws_sns_topic" "sns_topics" {
  for_each     = local.sns_topics
  name         = "${lower(var.environment)}_${each.key}"
  display_name = "${lower(var.environment)}_${each.key}"
  tags = {
    Name = "${lower(var.environment)}_${each.key}"
  }
}

############################
## SNS Topic Policies ##
############################

resource "aws_sns_topic_policy" "sns_topics" {
  for_each = local.sns_topics
  arn      = resource.aws_sns_topic.sns_topics[each.key].arn

  policy = data.aws_iam_policy_document.sns_topic_policies[each.key].json
}

######################################
## SNS Topic Policies Documents ##
######################################

data "aws_iam_policy_document" "sns_topic_policies" {
  for_each  = local.sns_topics
  policy_id = "__default_policy_ID"

  version = "2008-10-17"

  statement {
    sid = "__default_statement_ID"

    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "SNS:Publish",
      "SNS:RemovePermission",
      "SNS:SetTopicAttributes",
      "SNS:DeleteTopic",
      "SNS:ListSubscriptionsByTopic",
      "SNS:GetTopicAttributes",
      "SNS:Receive",
      "SNS:AddPermission",
      "SNS:Subscribe"
    ]

    resources = [resource.aws_sns_topic.sns_topics[each.key].arn]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"

      values = [
        data.aws_caller_identity.current.account_id,
      ]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"

      values = [
        "arn:aws:s3:::${each.value}"
      ]
    }
  }

  statement {
    sid    = "__console_pub_0"
    effect = "Allow"


    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions = [
      "SNS:Subscribe",
      "SNS:Receive",
      "SNS:Publish"
    ]

    resources = [resource.aws_sns_topic.sns_topics[each.key].arn]
  }
}

#########################
## Event Notifications ##
#########################

resource "aws_s3_bucket_notification" "nwm_bucket_notification" {
  bucket = var.nwm_data_bucket

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_ingest_ana"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "common/data/model/com/nwm/prod/"
    filter_suffix = "analysis_assim.channel_rt.tm00.conus.nc"
  }

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_ingest_ana_hi"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "common/data/model/com/nwm/prod/"
    filter_suffix = "analysis_assim.channel_rt.tm0000.hawaii.nc"
  }

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_ingest_ana_prvi"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "common/data/model/com/nwm/prod/"
    filter_suffix = "analysis_assim.channel_rt.tm00.puertorico.nc"
  }

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_ingest_srf"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "common/data/model/com/nwm/prod/"
    filter_suffix = "short_range.channel_rt.f018.conus.nc"
  }

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_ingest_srf_hi"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "common/data/model/com/nwm/prod/"
    filter_suffix = "short_range.channel_rt.f04800.hawaii.nc"
  }

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_ingest_srf_prvi"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "common/data/model/com/nwm/prod/"
    filter_suffix = "short_range.channel_rt.f048.puertorico.nc"
  }

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_ingest_mrf_3day"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "common/data/model/com/nwm/prod/"
    filter_suffix = "medium_range.channel_rt_1.f072.conus.nc"
  }

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_ingest_mrf_5day"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "common/data/model/com/nwm/prod/"
    filter_suffix = "medium_range.channel_rt_1.f120.conus.nc"
  }

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_ingest_mrf_10day"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "common/data/model/com/nwm/prod/"
    filter_suffix = "medium_range.channel_rt_1.f240.conus.nc"
  }
}

resource "aws_s3_bucket_notification" "nwm_max_flows_bucket_notification" {
  bucket = var.nwm_max_flows_data_bucket

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_max_flows"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "max_flows/"
    filter_suffix = "max_flows.nc"
  }
}

resource "aws_s3_bucket_notification" "rnr_max_flows_bucket_notification" {
  bucket = var.rnr_max_flows_data_bucket

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["rnr_max_flows"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "max_flows/"
    filter_suffix = "max_flows.csv"
  }
}

#############
## Outputs ##
#############

output "sns_topics" {
  value = { for k, v in resource.aws_sns_topic.sns_topics : k => v }
}
