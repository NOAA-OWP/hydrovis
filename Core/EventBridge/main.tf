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

#############
## Outputs ##
#############

output "scheduled_eventbridge_rules" {
  value = { for k, v in resource.aws_cloudwatch_event_rule.scheduled_events : k => v }
}
