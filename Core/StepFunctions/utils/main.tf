variable "environment" {
  type        = string
}

variable "region" {
  type        = string
}

variable "rds_bastion_id" {
  description = "ID of the RDS Bastion EC2 machine that the DB deploys will be executed from."
  type        = string
}

variable "test_wrds_db_lambda_arn" {
  type        = string
}

variable "sync_wrds_db_role" {
  type        = string
}

variable "aws_instances_to_reboot" {
  type        = list(string)
}

variable "email_sns_topics" {
  description = "SnS topics"
  type        = map(any)
}

####################################################
##     Ensure EC2 Ready For Use Step Function     ##
####################################################

resource "aws_sfn_state_machine" "ensure_ec2_ready_for_use_step_function" {
  name     = "hv-vpp-${var.environment}-ensure-ec2-ready-for-use"
  role_arn = var.sync_wrds_db_role

  definition = templatefile("${path.module}/ensure_ec2_ready.json.tftpl", {})
}

###################################################
##     Restore DB From S3 Dump Step Function     ##
###################################################

resource "aws_sfn_state_machine" "restore_db_from_s3_dump_step_function" {
  name     = "hv-vpp-${var.environment}-restore-db-from-s3"
  role_arn = var.sync_wrds_db_role

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
  role_arn = var.sync_wrds_db_role

  definition = templatefile("${path.module}/sync_wrds_location_db.json.tftpl", {
    restore_db_dump_from_s3_step_function_arn = aws_sfn_state_machine.restore_db_from_s3_dump_step_function.arn
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

################################################
##     Reboot EC2 Instances Step Function     ##
################################################

resource "aws_sfn_state_machine" "reboot_ec2_instances_step_function" {
    name     = "hv-vpp-${var.environment}-reboot-ec2-instances"
    role_arn = var.sync_wrds_db_role

    definition = templatefile("${path.module}/reboot_ec2_instances.json.tftpl", {
        aws_instances_to_reboot = var.aws_instances_to_reboot
    })
}

output "sync_wrds_location_db_step_function" {
  value = aws_sfn_state_machine.sync_wrds_location_db_step_function
}