###########################################
## All Scheduled Event EventBridge Rules ##
###########################################

resource "aws_cloudwatch_event_rule" "every_five_minutes" {
  name                = "every_five_minutes"
  description         = "Fires every 5 minutes"
  schedule_expression = "cron(0/5 * * * ? *)"
}

resource "aws_cloudwatch_event_rule" "every_fifteen_minutes" {
  name                = "every_fifteen_minutes"
  description         = "Fires every 15 minutes"
  schedule_expression = "cron(0/15 * * * ? *)"
}

#############
## Outputs ##
#############

output "five_minute_eventbridge" {
  value = aws_cloudwatch_event_rule.every_five_minutes
}

output "fifteen_minute_eventbridge" {
  value = aws_cloudwatch_event_rule.every_fifteen_minutes
}
