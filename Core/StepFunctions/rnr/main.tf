variable "rnr_lambda_role" {
  type        = string
}

variable "environment" {
  type        = string
}

variable "initialize_pipeline_arn" {
  type        = string
}

variable "rnr_domain_generator_arn" {
  type        = string
}

variable "rnr_ec2_instance" {
  type        = string
}

variable "fifteen_minute_trigger" {
  type = object({
    name = string
  })
}

#########################################
##     Replace Route Step Function     ##
#########################################

resource "aws_sfn_state_machine" "replace_route_step_function" {
    name     = "hv-vpp-${var.environment}-execute-replace-route"
    role_arn = var.rnr_lambda_role

    definition = templatefile("${path.module}/execute_replace_route.json.tftpl", {
        initialize_pipeline_arn = var.initialize_pipeline_arn
        rnr_domain_generator_arn = var.rnr_domain_generator_arn
        rnr_ec2_instance = var.rnr_ec2_instance
    })

    tags = {
      "noaa:monitoring" : "true"
    }
}

resource "aws_cloudwatch_event_target" "check_lambda_every_five_minutes" {
  count     = var.environment == "ti" ? 0 : 1
  rule      = var.fifteen_minute_trigger.name
  target_id = aws_sfn_state_machine.replace_route_step_function.name
  arn       = aws_sfn_state_machine.replace_route_step_function.arn
  role_arn  = aws_sfn_state_machine.replace_route_step_function.role_arn
}