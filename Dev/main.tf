terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.24"
    }
  }
}

# See ./sensitive/env.yaml for list of available variables
locals {
  env = yamldecode(file("./sensitive/env.yaml"))
}

provider "aws" {
  region                  = local.env.region
  profile                 = local.env.environment
  shared_credentials_files = ["/cloud/aws/credentials"]

  default_tags {
    tags = {
      CreatedBy    = "Terraform"
      hydrovis-env = "dev"
    }
  }
}

# Data Blocks

data "aws_security_group" "es-sg" {
  name = "es-sg"
}

data "aws_security_group" "ssm-session-manager-sg" {
  name = "ssm-session-manager-sg"
  tags = {
    VPC = "ti"
  }
}

data "aws_subnet" "hydrovis-sn-prv-data1a" {
  tags = {
    Name = "hydrovis-sn-prv-${local.env.environment}-data1a"
  }
}

data "aws_subnet" "hydrovis-sn-prv-data1b" {
  tags = {
    Name = "hydrovis-sn-prv-${local.env.environment}-data1b"
  }
}

data "aws_iam_instance_profile" "HydrovisSSMInstanceProfileRole" {
  name = "HydrovisSSMInstanceProfileRole"
}

data "aws_s3_bucket" "deployment" {
  bucket = "hydrovis-ti-deployment-us-east-1"
}

data "aws_lambda_function" "max_flows" {
  function_name = "viz_max_flows_ti"
}

data "aws_lambda_function" "hml_reciever" {
  function_name = "HML_Receiver__ti"
}

data "aws_lambda_function" "db_ingest" {
  function_name = "viz_db_ingest_ti"
}



# Monitoring Module
module "monitoring" {
  source = "./Monitoring"

  # General Variables
  environment     = local.env.environment
  account_id      = local.env.account_id
  region          = local.env.region
  es_sgs          = [data.aws_security_group.es-sg.id]
  data_subnet_ids = [
    data.aws_subnet.hydrovis-sn-prv-data1a.id,
    data.aws_subnet.hydrovis-sn-prv-data1b.id
  ]

  # DashboardUsersCredentials Module
  dashboard_users_and_roles = {
    wpod = ["readall", "opensearch_dashboards_read_only"]
  }

  # LogIngest Module
  ami_owner_account_id                = local.env.ami_owner_account_id
  logstash_instance_subnet_id         = data.aws_subnet.hydrovis-sn-prv-data1a.id
  logstash_instance_availability_zone = data.aws_subnet.hydrovis-sn-prv-data1a.availability_zone
  logstash_instance_profile_name      = data.aws_iam_instance_profile.HydrovisSSMInstanceProfileRole.name
  logstash_instance_sgs               = [
    data.aws_security_group.es-sg.id,
    data.aws_security_group.ssm-session-manager-sg.id
  ]
  deployment_bucket                   = data.aws_s3_bucket.deployment.bucket
  lambda_trigger_functions            = [
    data.aws_lambda_function.max_flows.function_name,
    data.aws_lambda_function.hml_reciever.function_name,
    data.aws_lambda_function.db_ingest.function_name
  ]
  buckets_and_parameters = {
    "hml" = {
      bucket_name         = "hydrovis-${local.env.environment}-hml-${local.env.region}"
      comparison_operator = "LessThanLowerThreshold"
    }
    "nwm" = {
      bucket_name         = "hydrovis-${local.env.environment}-nwm-${local.env.region}"
      comparison_operator = "LessThanLowerThreshold"
    }
    "pcpanl" = {
      bucket_name         = "hydrovis-${local.env.environment}-pcpanl-${local.env.region}"
      comparison_operator = "LessThanLowerThreshold"
    }
  }
}