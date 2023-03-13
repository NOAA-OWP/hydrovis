variable "environment" {
  type = string
}

variable "account_id" {
  type = string
}

variable "ami_owner_account_id" {
  type = string
}

variable "region" {
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
          AWS     = "arn:aws:iam::${var.ami_owner_account_id}:root"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "EC2ImageBuilderDistributionCrossAccountRole" {
  role       = aws_iam_role.EC2ImageBuilderDistributionCrossAccountRole.name
  policy_arn = "arn:aws:iam::aws:policy/Ec2ImageBuilderCrossAccountDistributionAccess"
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


# HydrovisSSMInstanceProfileRole Role
resource "aws_iam_role" "HydrovisSSMInstanceProfileRole" {
  name = "HydrovisSSMInstanceProfileRole_${var.region}"

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

resource "aws_iam_instance_profile" "HydrovisSSMInstanceProfileRole" {
  name = "HydrovisSSMInstanceProfileRole_${var.region}"
  role = aws_iam_role.HydrovisSSMInstanceProfileRole.name
}

resource "aws_iam_role_policy" "HydroVISSSMPolicy" {
  name   = "HydroVISSSMPolicy_${var.region}"
  role   = aws_iam_role.HydrovisSSMInstanceProfileRole.id
  policy = templatefile("${path.module}/HydroVISSSMPolicy.json.tftpl", {
    environment = var.environment
  })
}


# hydrovis-viz-proc-pipeline-lambda Role
resource "aws_iam_role" "hydrovis-viz-proc-pipeline-lambda" {
  name = "hydrovis-viz-proc-pipeline-lambda_${var.region}"

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

resource "aws_iam_role_policy" "hydrovis-viz-proc-pipeline-lambda" {
  name   = "hydrovis-viz-proc-pipeline-lambda_${var.region}"
  role   = aws_iam_role.hydrovis-viz-proc-pipeline-lambda.id
  policy = templatefile("${path.module}/hydrovis-viz-proc-pipeline-lambda.json.tftpl", {
    environment = var.environment
    account_id  = var.account_id
    region      = var.region
  })
}

resource "aws_iam_role_policy" "EventBridge-PassToService-Policy" {
  name   = "EventBridge-PassToService-Policy_${var.region}"
  role   = aws_iam_role.hydrovis-viz-proc-pipeline-lambda.id
  policy = templatefile("${path.module}/EventBridge-PassToService-Policy.json.tftpl", {})
}

resource "aws_iam_role_policy" "EventBridge-proc-pipeline-Lambda-Access" {
  name   = "EventBridge-proc-pipeline-Lambda-Access_${var.region}"
  role   = aws_iam_role.hydrovis-viz-proc-pipeline-lambda.id
  policy = templatefile("${path.module}/EventBridge-proc-pipeline-Lambda-Access.json.tftpl", {
    account_id  = var.account_id
  })
}

resource "aws_iam_role_policy_attachment" "hydrovis-viz-proc-pipeline-lambda-event-bridge" {
  role       = aws_iam_role.hydrovis-viz-proc-pipeline-lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess"
}

# hydrovis-rds-s3-export Role
resource "aws_iam_role" "hydrovis-rds-s3-export" {
  name = "hydrovis-rds-s3-export_${var.region}"

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

resource "aws_iam_role_policy" "hydrovis-rds-s3-export" {
  name   = "hydrovis-rds-s3-export_${var.region}"
  role   = aws_iam_role.hydrovis-rds-s3-export.id
  policy = templatefile("${path.module}/hydrovis-rds-s3-export.json.tftpl", {
    environment = var.environment
    account_id  = var.account_id
    region      = var.region
  })
}


# hydrovis-hml-ingest-role Role
resource "aws_iam_role" "hydrovis-hml-ingest-role" {
  name = "hydrovis-hml-ingest-role_${var.region}"

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


resource "aws_iam_instance_profile" "hydrovis-hml-ingest-role" {
  name = "hydrovis-hml-ingest-role_${var.region}"
  role = aws_iam_role.hydrovis-hml-ingest-role.name
}

resource "aws_iam_role_policy" "hydrovis-hml-ingest-role" {
  name   = "hydrovis-hml-ingest-role_${var.region}"
  role   = aws_iam_role.hydrovis-hml-ingest-role.id
  policy = templatefile("${path.module}/hydrovis-hml-ingest-role.json.tftpl", {
    environment = var.environment
    account_id  = var.account_id
    region      = var.region
  })
}

resource "aws_iam_role_policy" "hydrovis-hml-ingest-role-SSM-policy" {
  name   = "HydroVISSSMPolicy_${var.region}"
  role   = aws_iam_role.hydrovis-hml-ingest-role.id
  policy = templatefile("${path.module}/HydroVISSSMPolicy.json.tftpl", {
    environment = var.environment
  })
}

resource "aws_iam_role_policy_attachment" "hydrovis-hml-ingest-role-lambda-execute-policy" {
  role       = aws_iam_role.hydrovis-hml-ingest-role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


# Hydroviz-RnR-EC2-Profile Role
resource "aws_iam_role" "hydrovis-rnr-role" {
  name = "hydrovis-rnr-role_${var.region}"

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

resource "aws_iam_instance_profile" "hydrovis-rnr-role" {
  name = "hydrovis-rnr-role_${var.region}"
  role = aws_iam_role.hydrovis-rnr-role.name
}

resource "aws_iam_role_policy" "hydrovis-rnr-role-SSM-policy" {
  name   = "HydroVISSSMPolicy_${var.region}"
  role   = aws_iam_role.hydrovis-rnr-role.id
  policy = templatefile("${path.module}/HydroVISSSMPolicy.json.tftpl", {
    environment = var.environment
  })
}


#ECS Execution Role
resource "aws_iam_role" "hydrovis-ecs-task-execution" {
  name = "hydrovis-ecs-task-execution_${var.region}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

data "aws_iam_policy" "ecs_task_execution_policy" {
  name = "AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs-task-execution-policy" {
  name   = "ecs-task-execution-policy_${var.region}"
  role   = aws_iam_role.hydrovis-ecs-task-execution.id
  policy = data.aws_iam_policy.ecs_task_execution_policy.policy
}

resource "aws_iam_role_policy" "ecs-task-execution-cloudwatch-log-policy" {
  name   = "ecs-task-execution-cloudwatch-log-policy_${var.region}"
  role   = aws_iam_role.hydrovis-ecs-task-execution.id
  policy = templatefile("${path.module}/hydrovis-cloudwatch-log-template.json.tftpl", {})
}


# ECS Container Role
resource "aws_iam_role" "hydrovis-ecs-resource-access" {
  name = "hydrovis-ecs-resource-access_${var.region}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = [
            "ecs-tasks.amazonaws.com",
            "ecs.amazonaws.com"
          ]
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "hydrovis-ecs-task-cloudwatch-log-policy" {
  name   = "hydrovis-cloudwatch-log-policy_${var.region}"
  role   = aws_iam_role.hydrovis-ecs-resource-access.id
  policy = templatefile("${path.module}/hydrovis-cloudwatch-log-template.json.tftpl", {})
}


# hydrovis-sync-wrds-location-db Role
resource "aws_iam_role" "hydrovis-sync-wrds-location-db" {
  name = "hydrovis-sync-wrds-location-db_${var.region}"
  
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

resource "aws_iam_instance_profile" "hydrovis-sync-wrds-location-db" {
  name = "hydrovis-sync-wrds-location-db_${var.region}"
  role = aws_iam_role.hydrovis-sync-wrds-location-db.name
}

resource "aws_iam_role_policy" "hydrovis-sync-wrds-location-db-policy" {
  name   = "HydroVISSyncWrdsLocationDbPolicy_${var.region}"
  role   = aws_iam_role.hydrovis-sync-wrds-location-db.id
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

resource "aws_iam_role_policy_attachment" "hydrovis-sync-wrds-location-db" {
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
  role       = aws_iam_role.hydrovis-sync-wrds-location-db.name
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

output "role_hydrovis-viz-proc-pipeline-lambda" {
  value = aws_iam_role.hydrovis-viz-proc-pipeline-lambda
}

output "role_hydrovis-rds-s3-export" {
  value = aws_iam_role.hydrovis-rds-s3-export
}

output "role_HydrovisSSMInstanceProfileRole" {
  value = aws_iam_role.HydrovisSSMInstanceProfileRole
}

output "profile_HydrovisSSMInstanceProfileRole" {
  value = aws_iam_instance_profile.HydrovisSSMInstanceProfileRole
}

output "role_hydrovis-hml-ingest-role" {
  value = aws_iam_role.hydrovis-hml-ingest-role
}

output "profile_hydrovis-hml-ingest-role" {
  value = aws_iam_instance_profile.hydrovis-hml-ingest-role
}

output "role_hydrovis-rnr-role" {
  value = aws_iam_role.hydrovis-rnr-role
}

output "profile_hydrovis-rnr-role" {
  value = aws_iam_instance_profile.hydrovis-rnr-role
}

output "role_hydrovis-ecs-resource-access" {
  value = aws_iam_role.hydrovis-ecs-resource-access
}

output "role_hydrovis-ecs-task-execution" {
  value = aws_iam_role.hydrovis-ecs-task-execution
}

output "role_hydrovis-sync-wrds-location-db" {
  value = aws_iam_role.hydrovis-sync-wrds-location-db
}

output "profile_hydrovis-sync-wrds-location-db" {
  value = aws_iam_instance_profile.hydrovis-sync-wrds-location-db
}