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
  env = yamldecode(file(".env.yaml"))
}

provider "aws" {
  region                   = local.env.region
  profile                  = local.env.environment
  shared_credentials_files = ["/cloud/aws/credentials"]

  default_tags {
    tags = {
      CreatedBy    = "Terraform"
      hydrovis-env = "dev"
    }
  }
}

# Example Data Source Block
data "aws_vpc" "example_data_source" {
  tags = {
    Name = "hydrovis-${local.env.environment}-vpc"
  }
}

# Example Child Module
module "example" {
  source = "./example"

  environment  = local.env.environment
  account_id   = local.env.account_id
  region       = local.env.region

  example_data_source_id = data.example_data_source.id
}