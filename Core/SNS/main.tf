variable "environment" {
  description = "Hydrovis environment"
  type        = string
}

variable "nwm_data_bucket" {
  description = "S3 bucket for NWM data"
  type        = string
}

variable "nwm_max_values_data_bucket" {
  description = "S3 bucket for max flows data"
  type        = string
}


variable "rnr_max_flows_data_bucket" {
  description = "S3 bucket for rnr max flows data"
  type        = string
}

variable "error_email_list" {
  type = map(list(string))
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {

  sns_topics = {
    nwm_channel_ana       = tomap({ "sns_type" = "s3", "bucket" = var.nwm_data_bucket })
    nwm_forcing_ana       = tomap({ "sns_type" = "s3", "bucket" = var.nwm_data_bucket })
    nwm_channel_ana_hi    = tomap({ "sns_type" = "s3", "bucket" = var.nwm_data_bucket })
    nwm_forcing_ana_hi    = tomap({ "sns_type" = "s3", "bucket" = var.nwm_data_bucket })
    nwm_channel_ana_prvi  = tomap({ "sns_type" = "s3", "bucket" = var.nwm_data_bucket })
    nwm_forcing_ana_prvi  = tomap({ "sns_type" = "s3", "bucket" = var.nwm_data_bucket })
    nwm_channel_srf       = tomap({ "sns_type" = "s3", "bucket" = var.nwm_data_bucket })
    nwm_forcing_srf       = tomap({ "sns_type" = "s3", "bucket" = var.nwm_data_bucket })
    nwm_channel_srf_hi    = tomap({ "sns_type" = "s3", "bucket" = var.nwm_data_bucket })
    nwm_forcing_srf_hi    = tomap({ "sns_type" = "s3", "bucket" = var.nwm_data_bucket })
    nwm_channel_srf_prvi  = tomap({ "sns_type" = "s3", "bucket" = var.nwm_data_bucket })
    nwm_forcing_srf_prvi  = tomap({ "sns_type" = "s3", "bucket" = var.nwm_data_bucket })
    nwm_channel_mrf_3day  = tomap({ "sns_type" = "s3", "bucket" = var.nwm_data_bucket })
    nwm_channel_mrf_5day  = tomap({ "sns_type" = "s3", "bucket" = var.nwm_data_bucket })
    nwm_channel_mrf_10day = tomap({ "sns_type" = "s3", "bucket" = var.nwm_data_bucket })
    nwm_forcing_mrf       = tomap({ "sns_type" = "s3", "bucket" = var.nwm_data_bucket })
    rnr_max_flows         = tomap({ "sns_type" = "s3", "bucket" = var.rnr_max_flows_data_bucket })
    nwm_max_values         = tomap({ "sns_type" = "s3", "bucket" = var.nwm_max_values_data_bucket })
    viz_db_postprocess    = tomap({ "sns_type" = "lambda_trigger" })
  }

  email_list = flatten([
    for email_group_name, email_list in var.error_email_list : [
      for email in email_list : {
        email_group_name = email_group_name
        email            = email
      }
    ]
  ])
}

####################
## All SNS Topics ##
####################

resource "aws_sns_topic" "sns_topics" {
  for_each     = local.sns_topics
  name         = "${lower(var.environment)}_${each.key}"
  display_name = "${lower(var.environment)}_${each.key}"
  tags = {
    Name = "${lower(var.environment)}_${each.key}"
  }
}


###########################
## S3 SNS Topic Policies ##
###########################

resource "aws_sns_topic_policy" "s3_sns_topics" {
  for_each = {
    for topic_name, metadata in local.sns_topics : topic_name => metadata
    if metadata.sns_type == "s3"
  }
  arn = resource.aws_sns_topic.sns_topics[each.key].arn

  policy = data.aws_iam_policy_document.s3_sns_topic_policies[each.key].json
}

data "aws_iam_policy_document" "s3_sns_topic_policies" {
  for_each = {
    for topic_name, metadata in local.sns_topics : topic_name => metadata
    if metadata.sns_type == "s3"
  }

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
        "arn:aws:s3:::${each.value.bucket}"
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

#######################################
## Lambda Trigger SNS Topic Policies ##
#######################################

resource "aws_sns_topic_policy" "lambda_trigger_sns_topics" {
  for_each = {
    for topic_name, metadata in local.sns_topics : topic_name => metadata
    if metadata.sns_type == "lambda_trigger"
  }
  arn = resource.aws_sns_topic.sns_topics[each.key].arn

  policy = data.aws_iam_policy_document.lambda_trigger_sns_topic_policies[each.key].json
}

data "aws_iam_policy_document" "lambda_trigger_sns_topic_policies" {
  for_each = {
    for topic_name, metadata in local.sns_topics : topic_name => metadata
    if metadata.sns_type == "lambda_trigger"
  }

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
  }

  statement {
    sid    = "__console_sub_0"
    effect = "Allow"


    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions = [
      "SNS:Subscribe"
    ]

    resources = [resource.aws_sns_topic.sns_topics[each.key].arn]
  }
}

##############################
## Email SNS Topic Policies ##
##############################


resource "aws_sns_topic" "email_sns_topics" {
  for_each     = var.error_email_list
  name         = "${lower(var.environment)}_${each.key}"
  display_name = "${lower(var.environment)}_${each.key}"
  tags = {
    Name = "${lower(var.environment)}_${each.key}"
  }
}

resource "aws_sns_topic_policy" "email_sns_topics" {
  for_each = var.error_email_list
  arn      = resource.aws_sns_topic.email_sns_topics[each.key].arn

  policy = data.aws_iam_policy_document.email_sns_topic_policies[each.key].json
}

data "aws_iam_policy_document" "email_sns_topic_policies" {
  for_each = var.error_email_list

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
      "SNS:AddPermission",
      "SNS:Subscribe"
    ]

    resources = [resource.aws_sns_topic.email_sns_topics[each.key].arn]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"

      values = [
        data.aws_caller_identity.current.account_id,
      ]
    }
  }
}

resource "aws_sns_topic_subscription" "email-targets" {
  count = length(local.email_list)

  topic_arn = resource.aws_sns_topic.email_sns_topics[local.email_list[count.index].email_group_name].arn
  protocol  = "email"
  endpoint  = local.email_list[count.index].email
}


#########################
## Event Notifications ##
#########################

resource "aws_s3_bucket_notification" "nwm_bucket_notification" {
  bucket = var.nwm_data_bucket

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_channel_ana"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "common/data/model/com/nwm/prod/"
    filter_suffix = "analysis_assim.channel_rt.tm00.conus.nc"
  }

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_forcing_ana"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "common/data/model/com/nwm/prod/"
    filter_suffix = "analysis_assim.forcing.tm00.conus.nc"
  }

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_channel_ana_hi"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "common/data/model/com/nwm/prod/"
    filter_suffix = "analysis_assim.channel_rt.tm0000.hawaii.nc"
  }

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_forcing_ana_hi"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "common/data/model/com/nwm/prod/"
    filter_suffix = "analysis_assim.forcing.tm00.hawaii.nc"
  }

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_channel_ana_prvi"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "common/data/model/com/nwm/prod/"
    filter_suffix = "analysis_assim.channel_rt.tm00.puertorico.nc"
  }

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_forcing_ana_prvi"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "common/data/model/com/nwm/prod/"
    filter_suffix = "analysis_assim.forcing.tm00.puertorico.nc"
  }

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_channel_srf"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "common/data/model/com/nwm/prod/"
    filter_suffix = "short_range.channel_rt.f018.conus.nc"
  }

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_forcing_srf"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "common/data/model/com/nwm/prod/"
    filter_suffix = "short_range.forcing.f018.conus.nc"
  }

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_channel_srf_hi"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "common/data/model/com/nwm/prod/"
    filter_suffix = "short_range.channel_rt.f04800.hawaii.nc"
  }

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_forcing_srf_hi"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "common/data/model/com/nwm/prod/"
    filter_suffix = "short_range.forcing.f048.hawaii.nc"
  }

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_channel_srf_prvi"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "common/data/model/com/nwm/prod/"
    filter_suffix = "short_range.channel_rt.f048.puertorico.nc"
  }

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_forcing_srf_prvi"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "common/data/model/com/nwm/prod/"
    filter_suffix = "short_range.forcing.f048.puertorico.nc"
  }

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_channel_mrf_3day"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "common/data/model/com/nwm/prod/"
    filter_suffix = "medium_range.channel_rt_1.f072.conus.nc"
  }

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_channel_mrf_5day"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "common/data/model/com/nwm/prod/"
    filter_suffix = "medium_range.channel_rt_1.f120.conus.nc"
  }

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_channel_mrf_10day"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "common/data/model/com/nwm/prod/"
    filter_suffix = "medium_range.channel_rt_1.f240.conus.nc"
  }

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_forcing_mrf"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "common/data/model/com/nwm/prod/"
    filter_suffix = "medium_range.forcing.f240.conus.nc"
  }
}

resource "aws_s3_bucket_notification" "nwm_max_values_bucket_notification" {
  bucket = var.nwm_max_values_data_bucket

  topic {
    topic_arn     = resource.aws_sns_topic.sns_topics["nwm_max_values"].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "max_values/"
    filter_suffix = "max_values.nc"
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

output "email_sns_topics" {
  value = { for k, v in resource.aws_sns_topic.email_sns_topics : k => v }
}
