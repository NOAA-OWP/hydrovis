variable "lambda_role" {
  type        = string
}

variable "environment" {
  type        = string
}

variable "max_flows_arn" {
  type        = string
}

variable "schism_fim_processing_arn" {
  type        = string
}

variable "optimize_rasters_arn" {
  type        = string
}

variable "update_egis_data_arn" {
  type        = string
}

variable "fim_data_prep_arn" {
  type        = string
}

variable "hand_fim_processing_arn" {
  type        = string
}

variable "db_postprocess_sql_arn" {
  type        = string
}

variable "db_ingest_arn" {
  type        = string
}

variable "raster_processing_arn" {
  type        = string
}

variable "publish_service_arn" {
  type        = string
}

variable "email_sns_topics" {
  description = "SnS topics"
  type        = map(any)
}

##################################################
##     Viz Process Schism FIM Step Function     ##
##################################################

resource "aws_sfn_state_machine" "schism_fim_processing_step_function" {
    name     = "process_schism_fim_${var.environment}"
    role_arn = var.lambda_role

    definition = templatefile("${path.module}/schism_fim_processing.json.tftpl", {
        schism_fim_processing_arn = var.schism_fim_processing_arn
        optimize_rasters_arn      = var.optimize_rasters_arn
        update_egis_data_arn  = var.update_egis_data_arn
    })
}

########################################
##     Viz Pipeline Step Function     ##
########################################

resource "aws_sfn_state_machine" "viz_pipeline_step_function" {
    name     = "viz_pipeline_${var.environment}"
    role_arn = var.lambda_role

    definition = templatefile("${path.module}/viz_processing_pipeline.json.tftpl", {
        max_flows_arn = var.max_flows_arn
        db_postprocess_sql_arn = var.db_postprocess_sql_arn
        db_ingest_arn      = var.db_ingest_arn
        raster_processing_arn = var.raster_processing_arn
        optimize_rasters_arn      = var.optimize_rasters_arn
        fim_data_prep_arn  = var.fim_data_prep_arn
        update_egis_data_arn  = var.update_egis_data_arn
        publish_service_arn  = var.publish_service_arn
        schism_fim_processing_step_function_arn = aws_sfn_state_machine.schism_fim_processing_step_function.arn
        hand_fim_processing_step_function_arn = aws_sfn_state_machine.hand_fim_processing_step_function.arn
    })
}

###############################################
##     HAND FIM Processing Step Function     ##
###############################################

resource "aws_sfn_state_machine" "hand_fim_processing_step_function" {
    name     = "hand_fim_processing_${var.environment}"
    role_arn = var.lambda_role

    definition = templatefile("${path.module}/hand_fim_processing.json.tftpl", {
        fim_data_prep_arn  = var.fim_data_prep_arn
        hand_fim_processing_arn = var.hand_fim_processing_arn
    })
}

####### Step Function Failure / Time Out SNS #######
resource "aws_cloudwatch_event_rule" "viz_pipeline_step_function_failure" {
  name        = "viz_pipeline_step_function_failure_${var.environment}"
  description = "Alert when the viz step function times out or fails."

  event_pattern = <<EOF
  {
  "source": ["aws.states"],
  "detail-type": ["Step Functions Execution Status Change"],
  "detail": {
    "status": ["FAILED", "TIMED_OUT"],
    "stateMachineArn": ["${aws_sfn_state_machine.viz_pipeline_step_function.arn}"]
    }
  }
  EOF
}

resource "aws_cloudwatch_event_target" "step_function_failure_sns" {
  rule        = aws_cloudwatch_event_rule.viz_pipeline_step_function_failure.name
  target_id   = "SendToSNS"
  arn         = var.email_sns_topics["viz_lambda_errors"].arn
  input_path  = "$.detail.name"
}

output "hand_fim_processing_step_function" {
  value = aws_sfn_state_machine.hand_fim_processing_step_function
}

output "viz_pipeline_step_function" {
  value = aws_sfn_state_machine.viz_pipeline_step_function
}

output "schism_fim_processing_step_function" {
  value = aws_sfn_state_machine.schism_fim_processing_step_function
}