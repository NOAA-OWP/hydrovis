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

data "template_file" "HydrovisESRISSMDeploy-template" {
  template = file("${path.module}/HydrovisESRISSMDeploy-template.json")
  vars = {
    environment = var.environment
    region      = var.region
    account_id  = var.account_id
  }
}

resource "aws_iam_role_policy" "HydrovisESRISSMDeploy" {
  name   = "HydrovisESRISSMDeploy"
  role   = aws_iam_role.HydrovisESRISSMDeploy.id
  policy = data.template_file.HydrovisESRISSMDeploy-template.rendered
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

data "template_file" "HydroVISSSMPolicy-template" {
  template = file("${path.module}/HydroVISSSMPolicy-template.json")
  vars = {
    environment = var.environment
  }
}

resource "aws_iam_role_policy" "HydroVISSSMPolicy" {
  name   = "HydroVISSSMPolicy"
  role   = aws_iam_role.HydrovisSSMInstanceProfileRole.id
  policy = data.template_file.HydroVISSSMPolicy-template.rendered
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
            "apigateway.amazonaws.com"
          ]
        }
      },
    ]
  })
}

data "template_file" "hydrovis-viz-proc-pipeline-lambda-template" {
  template = file("${path.module}/hydrovis-viz-proc-pipeline-lambda-template.json")
  vars = {
    environment = var.environment
    account_id  = var.account_id
    region      = var.region
  }
}

resource "aws_iam_role_policy" "hydrovis-viz-proc-pipeline-lambda" {
  name   = "hydrovis-viz-proc-pipeline-lambda"
  role   = aws_iam_role.hydrovis-viz-proc-pipeline-lambda.id
  policy = data.template_file.hydrovis-viz-proc-pipeline-lambda-template.rendered
}

data "template_file" "EventBridge-PassToService-Policy-template" {
  template = file("${path.module}/EventBridge-PassToService-Policy-template.json")
}

resource "aws_iam_role_policy" "EventBridge-PassToService-Policy" {
  name   = "EventBridge-PassToService-Policy"
  role   = aws_iam_role.hydrovis-viz-proc-pipeline-lambda.id
  policy = data.template_file.EventBridge-PassToService-Policy-template.rendered
}

data "template_file" "EventBridge-proc-pipeline-Lambda-Access-template" {
  template = file("${path.module}/EventBridge-proc-pipeline-Lambda-Access-template.json")
  vars = {
    account_id  = var.account_id
  }
}

resource "aws_iam_role_policy" "EventBridge-proc-pipeline-Lambda-Access" {
  name   = "EventBridge-proc-pipeline-Lambda-Access"
  role   = aws_iam_role.hydrovis-viz-proc-pipeline-lambda.id
  policy = data.template_file.EventBridge-proc-pipeline-Lambda-Access-template.rendered
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

data "template_file" "hydrovis-hml-ingest-role-template" {
  template = file("${path.module}/hydrovis-hml-ingest-role-template.json")
  vars = {
    environment = var.environment
    account_id  = var.account_id
    region      = var.region
  }
}

resource "aws_iam_role_policy" "hydrovis-hml-ingest-role" {
  name   = "hydrovis-hml-ingest-role"
  role   = aws_iam_role.hydrovis-hml-ingest-role.id
  policy = data.template_file.hydrovis-hml-ingest-role-template.rendered
}

resource "aws_iam_role_policy" "hydrovis-hml-ingest-role-SSM-policy" {
  name   = "HydroVISSSMPolicy"
  role   = aws_iam_role.hydrovis-hml-ingest-role.id
  policy = data.template_file.HydroVISSSMPolicy-template.rendered
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
  policy = data.template_file.HydroVISSSMPolicy-template.rendered
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