variable "environment" {
  type = string
}

variable "account_id" {
  type = string
}

variable "ti_account_id" {
  type = string
}

variable "uat_account_id" {
  type = string
}

variable "prod_account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "nws_shared_account_s3_bucket" {
  type = string
}

variable "viz_proc_admin_rw_secret_arn" {
  type = string
}

# Autoscaling Role
resource "aws_iam_service_linked_role" "autoscaling" {
  aws_service_name = "autoscaling.amazonaws.com"
  custom_suffix    = "hvegis_${var.region}"

  lifecycle {
    ignore_changes = [custom_suffix]
  }
}


# EC2ImageBuilderDistributionCrossAccountRole Role
resource "aws_iam_role" "EC2ImageBuilderDistributionCrossAccountRole" {
  name = "EC2ImageBuilderDistributionCrossAccountRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
          AWS     = var.ti_account_id != "" ? [
            "arn:aws:iam::${var.ti_account_id}:root",
            "arn:aws:iam::${var.uat_account_id}:root",
            "arn:aws:iam::${var.prod_account_id}:root"
          ] : [
            "arn:aws:iam::${var.uat_account_id}:root",
            "arn:aws:iam::${var.prod_account_id}:root"
          ]
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "EC2ImageBuilderDistributionCrossAccountRole" {
  role       = aws_iam_role.EC2ImageBuilderDistributionCrossAccountRole.name
  policy_arn = "arn:aws:iam::aws:policy/Ec2ImageBuilderCrossAccountDistributionAccess"
}


# SSM Policy
resource "aws_iam_policy" "ssm" {
  name   = "hv-vpp-${var.environment}-${var.region}-ssm"
  policy = templatefile("${path.module}/ssm.json.tftpl", {
    environment = var.environment
  })
}


# HydrovisESRISSMDeploy Role
resource "aws_iam_role" "HydrovisESRISSMDeploy" {
  name = "HydrovisESRISSMDeploy_${var.region}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_instance_profile" "HydrovisESRISSMDeploy" {
  name = "HydrovisESRISSMDeploy_${var.region}"
  role = aws_iam_role.HydrovisESRISSMDeploy.name
}

resource "aws_iam_role_policy" "HydrovisESRISSMDeploy" {
  name   = "HydrovisESRISSMDeploy_${var.region}"
  role   = aws_iam_role.HydrovisESRISSMDeploy.id
  policy = templatefile("${path.module}/HydrovisESRISSMDeploy.json.tftpl", {
    environment = var.environment
    region      = var.region
    account_id  = var.account_id
  })
}

resource "aws_iam_role_policy_attachment" "HydrovisESRISSMDeploy_cloudwatch" {
  role       = aws_iam_role.HydrovisESRISSMDeploy.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}


# viz-pipeline Role
resource "aws_iam_role" "viz_pipeline" {
  name = "hv-vpp-${var.environment}-${var.region}-viz-pipeline"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "events.amazonaws.com",
            "apigateway.amazonaws.com",
            "sagemaker.amazonaws.com",
            "states.amazonaws.com",
            "codebuild.amazonaws.com"
          ]
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "viz_pipeline" {
  name   = "hv-vpp-${var.environment}-${var.region}-viz-pipeline"
  role   = aws_iam_role.viz_pipeline.id
  policy = templatefile("${path.module}/viz_pipeline.json.tftpl", {
    environment                   = var.environment
    account_id                    = var.account_id
    region                        = var.region
    nws_shared_account_s3_bucket  = var.nws_shared_account_s3_bucket
  })
}

resource "aws_iam_role_policy" "viz_pipeline_eventbridge_access_custom" {
  name   = "hv-vpp-${var.environment}-${var.region}-viz-pipeline-eventbridge-access"
  role   = aws_iam_role.viz_pipeline.id
  policy = templatefile("${path.module}/eventbridge_access.json.tftpl", {
    account_id  = var.account_id
  })
}

resource "aws_iam_role_policy_attachment" "viz_pipeline_eventbridge_access" {
  role       = aws_iam_role.viz_pipeline.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess"
}


# rds-s3-export Role
resource "aws_iam_role" "rds_s3_export" {
  name = "hv-vpp-${var.environment}-${var.region}-rds-s3-export"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "rds.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "rds_s3_export" {
  name   = "hv-vpp-${var.environment}-${var.region}-rds-s3-export"
  role   = aws_iam_role.rds_s3_export.id
  policy = templatefile("${path.module}/rds_s3_export.json.tftpl", {
    environment = var.environment
    account_id  = var.account_id
    region      = var.region
  })
}

# Redshift Role
resource "aws_iam_role" "redshift" {
  name = "hv-vpp-${var.environment}-${var.region}-redshift"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "redshift.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "redshift" {
  name   = "hv-vpp-${var.environment}-${var.region}-redshift"
  role   = aws_iam_role.redshift.id
  policy = templatefile("${path.module}/redshift.json.tftpl", {
    environment                  = var.environment
    account_id                   = var.account_id
    region                       = var.region
    viz_proc_admin_rw_secret_arn = var.viz_proc_admin_rw_secret_arn
  })
}

# data-services Role
resource "aws_iam_role" "data_services" {
  name = "hv-vpp-${var.environment}-${var.region}-data-services"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_instance_profile" "data_services" {
  name = "hv-vpp-${var.environment}-${var.region}-data-services"
  role = aws_iam_role.data_services.name
}

resource "aws_iam_role_policy_attachment" "data_services_ssm" {
  role       = aws_iam_role.data_services.name
  policy_arn = aws_iam_policy.ssm.arn
}

resource "aws_iam_role_policy_attachment" "data_services_cloudwatch" {
  role       = aws_iam_role.data_services.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}


# data-ingest Role
resource "aws_iam_role" "data_ingest" {
  name = "hv-vpp-${var.environment}-${var.region}-data-ingest"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = ["ec2.amazonaws.com", "lambda.amazonaws.com"]
        }
      },
    ]
  })
}

resource "aws_iam_instance_profile" "data_ingest" {
  name = "hv-vpp-${var.environment}-${var.region}-data-ingest"
  role = aws_iam_role.data_ingest.name
}

resource "aws_iam_role_policy" "data_ingest" {
  name   = "hv-vpp-${var.environment}-${var.region}-data-ingest"
  role   = aws_iam_role.data_ingest.id
  policy = templatefile("${path.module}/data_ingest.json.tftpl", {
    environment                   = var.environment
    account_id                    = var.account_id
    region                        = var.region
    nws_shared_account_s3_bucket  = var.nws_shared_account_s3_bucket
  })
}

resource "aws_iam_role_policy_attachment" "data_ingest_ssm" {
  role       = aws_iam_role.data_ingest.name
  policy_arn = aws_iam_policy.ssm.arn
}

resource "aws_iam_role_policy_attachment" "data_ingest_lambda" {
  role       = aws_iam_role.data_ingest.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "data_ingest_cloudwatch" {
  role       = aws_iam_role.data_ingest.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}


# rnr Role
resource "aws_iam_role" "rnr" {
  name = "hv-vpp-${var.environment}-${var.region}-rnr"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_instance_profile" "rnr" {
  name = "hv-vpp-${var.environment}-${var.region}-rnr"
  role = aws_iam_role.rnr.name
}

resource "aws_iam_role_policy_attachment" "rnr_ssm" {
  role       = aws_iam_role.rnr.name
  policy_arn = aws_iam_policy.ssm.arn
}

resource "aws_iam_role_policy_attachment" "rnr_cloudwatch" {
  role       = aws_iam_role.rnr.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}


# sync-wrds-location-db Role
resource "aws_iam_role" "sync_wrds_location_db" {
  name = "hv-vpp-${var.environment}-${var.region}-sync-wrds-location-db"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = [
            "events.amazonaws.com",
            "scheduler.amazonaws.com",
            "lambda.amazonaws.com",
            "datasync.amazonaws.com",
            "states.amazonaws.com",
            "ec2.amazonaws.com"
          ]
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "sync_wrds_location_db" {
  name = "hv-vpp-${var.environment}-${var.region}-sync-wrds-location-db"
  role = aws_iam_role.sync_wrds_location_db.name
}

resource "aws_iam_role_policy" "sync_wrds_location_db" {
  name   = "hv-vpp-${var.environment}-${var.region}-sync-wrds-location-db"
  role   = aws_iam_role.sync_wrds_location_db.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        "Effect": "Allow",
        "Action": [
          "kms:CreateGrant"
        ],
        "Resource": "*",
        "Condition": {
          "Bool": {
            "kms:GrantIsForAWSResource": true
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sync_wrds_location_db" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonRDSFullAccess",
    "arn:aws:iam::aws:policy/AmazonEC2FullAccess",
    "arn:aws:iam::aws:policy/SecretsManagerReadWrite",
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
    "arn:aws:iam::aws:policy/service-role/AmazonSSMAutomationRole",
    "arn:aws:iam::aws:policy/service-role/AWSLambdaRole",
    "arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess",
    "arn:aws:iam::aws:policy/CloudWatchEventsFullAccess",
    "arn:aws:iam::aws:policy/AmazonEventBridgeSchedulerFullAccess",
    "arn:aws:iam::aws:policy/AWSLambda_FullAccess"
  ])
  role       = aws_iam_role.sync_wrds_location_db.name
  policy_arn = each.value
}


output "role_autoscaling" {
  value = aws_iam_service_linked_role.autoscaling
}

output "role_HydrovisESRISSMDeploy" {
  value = aws_iam_role.HydrovisESRISSMDeploy
}

output "profile_HydrovisESRISSMDeploy" {
  value = aws_iam_instance_profile.HydrovisESRISSMDeploy
}

output "role_data_services" {
  value = aws_iam_role.data_services
}

output "role_viz_pipeline" {
  value = aws_iam_role.viz_pipeline
}

output "role_rds_s3_export" {
  value = aws_iam_role.rds_s3_export
}

output "role_redshift" {
  value = aws_iam_role.redshift
}

output "profile_data_services" {
  value = aws_iam_instance_profile.data_services
}

output "role_data_ingest" {
  value = aws_iam_role.data_ingest
}

output "profile_data_ingest" {
  value = aws_iam_instance_profile.data_ingest
}

output "role_rnr" {
  value = aws_iam_role.rnr
}

output "profile_rnr" {
  value = aws_iam_instance_profile.rnr
}

output "role_sync_wrds_location_db" {
  value = aws_iam_role.sync_wrds_location_db
}