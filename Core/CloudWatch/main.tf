###############
## Variables ##
###############

variable "environment" {
  description = "Hydrovis environment"
  type        = string
}

variable "account_id" {
  type        = string
}

variable "region" {
  description = "Hydrovis region"
  type        = string
}

##########################
## CloudWatch Log Group ##
##########################

resource "aws_cloudwatch_log_group" "viz_processing_pipeline_log_group" {
  name = "hv-vpp-${var.environment}-${var.region}-viz-processing-pipeline"
}

output "viz_processing_pipeline_log_group" {
  value = aws_cloudwatch_log_group.viz_processing_pipeline_log_group
}
