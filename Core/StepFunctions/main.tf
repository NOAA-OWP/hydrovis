variable "viz_lambda_role" {
  type        = string
}

variable "rnr_lambda_role" {
  type        = string
}

variable "environment" {
  type        = string
}

variable "python_preprocessing_3GB_arn" {
  type        = string
}

variable "python_preprocessing_10GB_arn" {
  type        = string
}

variable "schism_fim_job_definition_arn" {
  type        = string
}

variable "schism_fim_job_queue_arn" {
  type        = string
}

variable "schism_fim_datasets_bucket" {
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

variable "initialize_pipeline_arn" {
  type        = string
}

variable "rnr_domain_generator_arn" {
  type        = string
}

variable "email_sns_topics" {
  description = "SnS topics"
  type        = map(any)
}

variable "aws_instances_to_reboot" {
  type        = list(string)
}

variable "fifteen_minute_trigger" {
  type = object({
    name = string
  })
}

variable "viz_processing_pipeline_log_group" {
  type        = string
}

variable "rds_bastion_id" {
  description = "ID of the RDS Bastion EC2 machine that the DB deploys will be executed from."
  type        = string
}

variable "test_wrds_db_lambda_arn" {
  type        = string
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
        rnr_ec2_instance = var.aws_instances_to_reboot[0]
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

################################################
##     Reboot EC2 Instances Step Function     ##
################################################

resource "aws_sfn_state_machine" "reboot_ec2_instances_step_function" {
    name     = "hv-vpp-${var.environment}-reboot-ec2-instances"
    role_arn = var.rnr_lambda_role

    definition = templatefile("${path.module}/reboot_ec2_instances.json.tftpl", {
        aws_instances_to_reboot = var.aws_instances_to_reboot
    })
}

resource "aws_cloudwatch_event_rule" "daily_at_2330" {
  name                = "daily_at_2330"
  description         = "Fires every day at 23:30"
  schedule_expression = "cron(30 23 * * ? *)"
}

resource "aws_cloudwatch_event_target" "trigger_reboot_rnr_ec2" {
  rule      = aws_cloudwatch_event_rule.daily_at_2330.name
  arn       = aws_sfn_state_machine.reboot_ec2_instances_step_function.arn
  role_arn  = var.rnr_lambda_role
}

##################################################
##     Viz Process Schism FIM Step Function     ##
##################################################

resource "aws_sfn_state_machine" "schism_fim_processing_step_function" {
    name     = "hv-vpp-${var.environment}-process-schism-fim"
    role_arn = var.viz_lambda_role

    definition = templatefile("${path.module}/schism_fim_processing.json.tftpl", {
        db_postprocess_sql_arn          = var.db_postprocess_sql_arn
        schism_fim_job_definition_arn   = var.schism_fim_job_definition_arn
        schism_fim_job_queue_arn        = var.schism_fim_job_queue_arn
        optimize_rasters_arn            = var.optimize_rasters_arn
        schism_fim_datasets_bucket      = var.schism_fim_datasets_bucket
    })
}

########################################
##     Viz Pipeline Step Function     ##
########################################

resource "aws_sfn_state_machine" "viz_pipeline_step_function" {
    name     = "hv-vpp-${var.environment}-viz-pipeline"
    role_arn = var.viz_lambda_role

    definition = templatefile("${path.module}/viz_processing_pipeline.json.tftpl", {
        python_preprocessing_3GB_arn = var.python_preprocessing_3GB_arn
        python_preprocessing_10GB_arn = var.python_preprocessing_10GB_arn
        db_postprocess_sql_arn = var.db_postprocess_sql_arn
        db_ingest_arn      = var.db_ingest_arn
        raster_processing_arn = var.raster_processing_arn
        optimize_rasters_arn      = var.optimize_rasters_arn
        fim_data_prep_arn  = var.fim_data_prep_arn
        update_egis_data_arn  = var.update_egis_data_arn
        publish_service_arn  = var.publish_service_arn
        schism_fim_processing_step_function_arn = aws_sfn_state_machine.schism_fim_processing_step_function.arn
        hand_fim_processing_step_function_arn = aws_sfn_state_machine.hand_fim_processing_step_function.arn
        viz_processing_pipeline_log_group = var.viz_processing_pipeline_log_group
    })

    tags = {
      "noaa:monitoring" : "true"
    }
}

###############################################
##     HAND FIM Processing Step Function     ##
###############################################

resource "aws_sfn_state_machine" "hand_fim_processing_step_function" {
    name     = "hv-vpp-${var.environment}-hand-fim-processing"
    role_arn = var.viz_lambda_role

    definition = templatefile("${path.module}/hand_fim_processing.json.tftpl", {
        fim_data_prep_arn  = var.fim_data_prep_arn
        hand_fim_processing_arn = var.hand_fim_processing_arn
    })
}

####### Step Function Failure / Time Out SNS #######
resource "aws_cloudwatch_event_rule" "viz_pipeline_step_function_failure" {
  name        = "hv-vpp-${var.environment}-viz-pipeline-step-function-failure"
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

resource "aws_cloudwatch_event_target" "viz_pipeline_step_function_failure_sns" {
  rule        = aws_cloudwatch_event_rule.viz_pipeline_step_function_failure.name
  target_id   = "SendToSNS"
  arn         = var.email_sns_topics["viz_lambda_errors"].arn
  input_path  = "$.detail.name"
}

####################################################
##     Ensure EC2 Ready For Use Step Function     ##
####################################################

resource "aws_sfn_state_machine" "ensure_ec2_ready_for_use_step_function" {
  name     = "hv-vpp-${var.environment}-ensure-ec2-ready-for-use"
  role_arn = var.viz_lambda_role

  definition = templatefile("${path.module}/ensure_ec2_ready.json.tftpl", {})
}

###################################################
##     Restore DB From S3 Dump Step Function     ##
###################################################

resource "aws_sfn_state_machine" "restore_db_from_s3_dump_step_function" {
  name     = "hv-vpp-${var.environment}-restore-db-from-s3"
  role_arn = var.viz_lambda_role

  definition = templatefile("${path.module}/restore_db_from_s3_dump.json.tftpl", {
    ensure_ec2_ready_step_function_arn  = aws_sfn_state_machine.ensure_ec2_ready_for_use_step_function.arn
    rds_bastion_id = var.rds_bastion_id
    region = var.region
  })
}

#################################################
##     Sync WRDS Location DB Step Function     ##
#################################################

resource "aws_sfn_state_machine" "sync_wrds_location_db_step_function" {
  name     = "hv-vpp-${var.environment}-sync-wrds-location-db"
  role_arn = var.viz_lambda_role

  definition = templatefile("${path.module}/sync_wrds_location_db.json.tftpl", {
    restore_db_from_s3_dump_step_function_arn  = aws_sfn_state_machine.restore_db_from_s3_dump_step_function.arn
    test_wrds_db_lambda_arn = var.test_wrds_db_lambda_arn
    rds_bastion_id = var.rds_bastion_id
    region = var.region
  })
}

####### Step Function Failure / Time Out SNS #######
resource "aws_cloudwatch_event_rule" "sync_wrds_location_db_step_function_failure" {
  name        = "hv-vpp-${var.environment}-sync-wrds-location-db-step-function-failure"
  description = "Alert when the sync wrds location db step function times out or fails."

  event_pattern = <<EOF
  {
    "source": ["aws.states"],
    "detail-type": ["Step Functions Execution Status Change"],
    "detail": {
      "status": ["FAILED", "TIMED_OUT"],
      "stateMachineArn": ["${aws_sfn_state_machine.sync_wrds_location_db_step_function.arn}"]
    }
  }
  EOF
}

resource "aws_cloudwatch_event_target" "sync_wrds_location_db_step_function_failure_sns" {
  rule        = aws_cloudwatch_event_rule.sync_wrds_location_db_step_function_failure.name
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

output "reboot_ec2_instances_step_function" {
  value = aws_sfn_state_machine.reboot_ec2_instances_step_function
}