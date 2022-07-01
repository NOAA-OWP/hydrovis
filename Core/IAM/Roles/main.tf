variable "environment" {
  type = string
}

variable "account_id" {
  type = string
}

variable "region" {
  type = string
}

# Autoscaling Role
resource "aws_iam_service_linked_role" "autoscaling" {
  aws_service_name = "autoscaling.amazonaws.com"
  custom_suffix    = "hvegis"
}

# HydrovisESRISSMDeploy Role
resource "aws_iam_role" "HydrovisESRISSMDeploy" {
  name = "HydrovisESRISSMDeploy"

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
  name = "HydrovisESRISSMDeploy"
  role = aws_iam_role.HydrovisESRISSMDeploy.name
}

resource "aws_iam_role_policy" "HydrovisESRISSMDeploy" {
  name   = "HydrovisESRISSMDeploy"
  role   = aws_iam_role.HydrovisESRISSMDeploy.id
  policy = templatefile("${path.module}/HydrovisESRISSMDeploy.json.tftpl", {
    environment = var.environment
    region      = var.region
    account_id  = var.account_id
  })
}


# HydrovisSSMInstanceProfileRole Role
resource "aws_iam_role" "HydrovisSSMInstanceProfileRole" {
  name = "HydrovisSSMInstanceProfileRole"

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
  name = "HydrovisSSMInstanceProfileRole"
  role = aws_iam_role.HydrovisSSMInstanceProfileRole.name
}

resource "aws_iam_role_policy" "HydroVISSSMPolicy" {
  name   = "HydroVISSSMPolicy"
  role   = aws_iam_role.HydrovisSSMInstanceProfileRole.id
  policy = templatefile("${path.module}/HydroVISSSMPolicy.json.tftpl", {
    environment = var.environment
  })
}


# hydrovis-viz-proc-pipeline-lambda Role
resource "aws_iam_role" "hydrovis-viz-proc-pipeline-lambda" {
  name = "hydrovis-viz-proc-pipeline-lambda"

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
            "states.amazonaws.com"
          ]
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "hydrovis-viz-proc-pipeline-lambda" {
  name   = "hydrovis-viz-proc-pipeline-lambda"
  role   = aws_iam_role.hydrovis-viz-proc-pipeline-lambda.id
  policy = templatefile("${path.module}/hydrovis-viz-proc-pipeline-lambda.json.tftpl", {
    environment = var.environment
    account_id  = var.account_id
    region      = var.region
  })
}

resource "aws_iam_role_policy" "EventBridge-PassToService-Policy" {
  name   = "EventBridge-PassToService-Policy"
  role   = aws_iam_role.hydrovis-viz-proc-pipeline-lambda.id
  policy = templatefile("${path.module}/EventBridge-PassToService-Policy.json.tftpl", {})
}

resource "aws_iam_role_policy" "EventBridge-proc-pipeline-Lambda-Access" {
  name   = "EventBridge-proc-pipeline-Lambda-Access"
  role   = aws_iam_role.hydrovis-viz-proc-pipeline-lambda.id
  policy = templatefile("${path.module}/EventBridge-proc-pipeline-Lambda-Access.json.tftpl", {
    account_id  = var.account_id
  })
}

resource "aws_iam_role_policy_attachment" "hydrovis-viz-proc-pipeline-lambda-event-bridge" {
  role       = aws_iam_role.hydrovis-viz-proc-pipeline-lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess"
}


# hydrovis-hml-ingest-role Role
resource "aws_iam_role" "hydrovis-hml-ingest-role" {
  name = "hydrovis-${var.environment}-hml-ingest-role"

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
  name = "hydrovis-${var.environment}-hml-ingest-role"
  role = aws_iam_role.hydrovis-hml-ingest-role.name
}

resource "aws_iam_role_policy" "hydrovis-hml-ingest-role" {
  name   = "hydrovis-hml-ingest-role"
  role   = aws_iam_role.hydrovis-hml-ingest-role.id
  policy = templatefile("${path.module}/hydrovis-hml-ingest-role.json.tftpl", {
    environment = var.environment
    account_id  = var.account_id
    region      = var.region
  })
}

resource "aws_iam_role_policy" "hydrovis-hml-ingest-role-SSM-policy" {
  name   = "HydroVISSSMPolicy"
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
resource "aws_iam_role" "Hydroviz-RnR-EC2-Profile" {
  name = "Hydroviz-RnR-EC2-Profile"

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

resource "aws_iam_instance_profile" "Hydroviz-RnR-EC2-Profile" {
  name = "Hydroviz-RnR-EC2-Profile"
  role = aws_iam_role.Hydroviz-RnR-EC2-Profile.name
}

resource "aws_iam_role_policy" "Hydroviz-RnR-EC2-Profile-SSM-policy" {
  name   = "HydroVISSSMPolicy"
  role   = aws_iam_role.Hydroviz-RnR-EC2-Profile.id
  policy = templatefile("${path.module}/HydroVISSSMPolicy.json.tftpl", {
    environment = var.environment
  })
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

output "role_Hydroviz-RnR-EC2-Profile" {
  value = aws_iam_role.Hydroviz-RnR-EC2-Profile
}

output "profile_Hydroviz-RnR-EC2-Profile" {
  value = aws_iam_instance_profile.Hydroviz-RnR-EC2-Profile
}