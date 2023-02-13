variable "viz_initialize_pipeline_lambda" {}

locals {

  scheduled_rules = {
    channel_rt_analysis_assim_para       = tomap({ "description" = "AnA Channel CONUS at 45M Past hour", "schedule_expression" = "cron(45 0-23 * * ? *)"})
    forcing_analysis_assim_para       = tomap({ "description" = "AnA Forcing CONUS at 35M Past hour", "schedule_expression" = "cron(35 0-23 * * ? *)"})
    channel_rt_analysis_assim_hawaii_para       = tomap({ "description" = "AnA Channel Hawaii at 35M Past hour", "schedule_expression" = "cron(35 0-23 * * ? *)"})
    forcing_analysis_assim_hawaii_para       = tomap({ "description" = "AnA Forcing Hawaii at 30M Past hour", "schedule_expression" = "cron(30 0-23 * * ? *)"})
    channel_rt_analysis_assim_puertorico_para       = tomap({ "description" = "AnA Channel Puerto Rico at 55M Past hour", "schedule_expression" = "cron(55 0-23 * * ? *)"})
    forcing_analysis_assim_puertorico_para       = tomap({ "description" = "AnA Forcing Puerto Rico at 30M Past hour", "schedule_expression" = "cron(30 0-23 * * ? *)"})
    channel_rt_analysis_assim_alaska_para       = tomap({ "description" = "AnA Channel Alaska at 30M Past hour", "schedule_expression" = "cron(30 0-23 * * ? *)"})
    forcing_analysis_assim_alaska_para       = tomap({ "description" = "AnA Forcing Alaska at 25M Past hour", "schedule_expression" = "cron(25 0-23 * * ? *)"})
    channel_rt_short_range_para       = tomap({ "description" ="srf Channel CONUS at 1H55M Past hour", "schedule_expression" = "cron(55 0-23 * * ? *)"})
    forcing_short_range_para       = tomap({ "description" = "SRF Forcing CONUS at 1H35M Past hour", "schedule_expression" = "cron(35 0-23 * * ? *)"})
    channel_rt_short_range_hawaii_para       = tomap({ "description" = "srf Channel hawaii at 3H35M Past hour", "schedule_expression" = "cron(35 4,16 * * ? *)"})  # Adding additional hour delay for getting data to para. May need to revisit this when para data is on prod
    forcing_short_range_hawaii_para       = tomap({ "description" = "SRF Forcing Hawaii at 3H Past hour", "schedule_expression" = "cron(0 4,16 * * ? *)"})  # Adding additional hour delay for getting data to para. May need to revisit this when para data is on prod
    channel_rt_short_range_puertorico_para       = tomap({ "description" = "srf Channel puertorico at 3H05M Past hour", "schedule_expression" = "cron(5 10,22 * * ? *)"})  # Adding additional hour delay for getting data to para. May need to revisit this when para data is on prod
    forcing_short_range_puertorico_para       = tomap({ "description" = "SRF Forcing Puerto Rico at 3H Past hour", "schedule_expression" = "cron(0 10,22 * * ? *)"})  # Adding additional hour delay for getting data to para. May need to revisit this when para data is on prod
    channel_rt_short_range_alaska_para       = tomap({ "description" = "srf Channel Alaska at 1H45M Past hour", "schedule_expression" = "cron(45 2,5,8,11,14,17,20,23 * * ? *)"})  # Adding additional hour delay for getting data to para. May need to revisit this when para data is on prod
    forcing_short_range_alaska_para       = tomap({ "description" = "SRF Forcing Alaska at 1H20M Past hour", "schedule_expression" = "cron(20 2,5,8,11,14,17,20,23 * * ? *)"})  # Adding additional hour delay for getting data to para. May need to revisit this when para data is on prod
    channel_rt_medium_range_gfs_para       = tomap({ "description" = "MRF (GFS) Channel CONUS at 7H Past hour", "schedule_expression" = "cron(0 2,8,14,20 * * ? *)"})  # Adding additional hour delay for getting data to para. May need to revisit this when para data is on prod
    forcing_medium_range_gfs_para       = tomap({ "description" = "MRF (GFS) Forcing CONUS at 5H Past hour", "schedule_expression" = "cron(0 0,6,12,18 * * ? *)"})  # Adding additional hour delay for getting data to para. May need to revisit this when para data is on prod
    channel_rt_medium_range_gfs_alaska_para       = tomap({ "description" = "MRF (GFS) Channel Alaska at 6H25M Past hour", "schedule_expression" = "cron(25 1,7,13,19 * * ? *)"})  # Adding additional hour delay for getting data to para. May need to revisit this when para data is on prod
    forcing_medium_range_gfs_alaska_para       = tomap({ "description" = "MRF (GFS) Forcing Alaska at 5H10M Past hour", "schedule_expression" = "cron(10 0,6,12,18 * * ? *)"})  # Adding additional hour delay for getting data to para. May need to revisit this when para data is on prod
    channel_rt_medium_range_nbm_para       = tomap({ "description" = "MRF (NBM) Channel CONUS at 7H5M Past hour", "schedule_expression" = "cron(5 2,8,14,20 * * ? *)"})  # Adding additional hour delay for getting data to para. May need to revisit this when para data is on prod
    forcing_medium_range_nbm_para       = tomap({ "description" = "MRF (NBM) Forcing CONUS at 5H5M Past hour", "schedule_expression" = "cron(5 0,6,12,18 * * ? *)"})  # Adding additional hour delay for getting data to para. May need to revisit this when para data is on prod
    channel_rt_medium_range_nbm_alaska_para       = tomap({ "description" = "MRF (NBM) Channel Alaska at 6H15M Past hour", "schedule_expression" = "cron(15 1,7,13,19 * * ? *)"})  # Adding additional hour delay for getting data to para. May need to revisit this when para data is on prod
    forcing_medium_range_nbm_alaska_para       = tomap({ "description" = "MRF (NBM) Forcing Alaska at 5H15M Past hour", "schedule_expression" = "cron(15 0,6,12,18 * * ? *)"})  # Adding additional hour delay for getting data to para. May need to revisit this when para data is on prod
  }
}

###########################################
## All Scheduled Event EventBridge Rules ##
###########################################

resource "aws_cloudwatch_event_rule" "scheduled_events" {
  for_each     = local.scheduled_rules

  name                = each.key
  description         = each.value.description
  schedule_expression = each.value.schedule_expression
}

########################################
## Initialize Pipeline Lambda Target  ##
########################################

resource "aws_cloudwatch_event_target" "eventbridge_targets" {
  for_each     = local.scheduled_rules

  rule      = resource.aws_cloudwatch_event_rule.scheduled_events[each.key].name
  target_id = var.viz_initialize_pipeline_lambda.name
  arn       = var.viz_initialize_pipeline_lambda.arn
}

resource "aws_lambda_permission" "allow_eventbridge_targets" {
  for_each     = local.scheduled_rules

  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = var.viz_initialize_pipeline_lambda.name
  principal     = "events.amazonaws.com"
  source_arn    = resource.aws_cloudwatch_event_rule.scheduled_events[each.key].arn
}



#############
## Outputs ##
#############

output "scheduled_eventbridge_rules" {
  value = { for k, v in resource.aws_cloudwatch_event_rule.scheduled_events : k => v }
}
