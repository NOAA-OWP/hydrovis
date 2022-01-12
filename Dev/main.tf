terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "3.52"
    }
  }
}

# See ./sensitive/envs/env.ENV.yaml for list of available variables
locals {
  env = yamldecode(file("./sensitive/envs/env.${terraform.workspace}.yaml"))
}

provider "aws" {
  region                  = local.env.region
  profile                 = local.env.environment
  shared_credentials_file = "/cloud/aws/credentials"
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