variable "viz_initialize_pipeline_lambda" {}

variable "scheduled_rules" {
  type = map(map(string))
}


###########################################
## All Scheduled Event EventBridge Rules ##
###########################################

resource "aws_cloudwatch_event_rule" "scheduled_events" {
  for_each = var.scheduled_rules

  name                = each.key
  description         = each.value.description
  schedule_expression = each.value.schedule_expression
}

########################################
## Initialize Pipeline Lambda Target  ##
########################################

resource "aws_cloudwatch_event_target" "eventbridge_targets" {
  for_each = var.scheduled_rules

  rule      = aws_cloudwatch_event_rule.scheduled_events[each.key].name
  target_id = var.viz_initialize_pipeline_lambda.function_name
  arn       = var.viz_initialize_pipeline_lambda.arn
}

resource "aws_lambda_permission" "allow_eventbridge_targets" {
  for_each = var.scheduled_rules

  statement_id_prefix  = "AllowExecutionFromCloudWatch"
  action               = "lambda:InvokeFunction"
  function_name        = var.viz_initialize_pipeline_lambda.function_name
  principal            = "events.amazonaws.com"
  source_arn           = aws_cloudwatch_event_rule.scheduled_events[each.key].arn
}



#############
## Outputs ##
#############

output "scheduled_eventbridge_rules" {
  value = { for k, v in resource.aws_cloudwatch_event_rule.scheduled_events : k => v }
}
