terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.24"
    }
  }
  backend "s3" {
    bucket                  = "hydrovis-terraform-state-us-east-1"
    key                     = "image-builder"
    region                  = "us-east-1"
    profile                 = "prod"
    shared_credentials_file = "/cloud/aws/credentials"
  }
}

# See ./sensitive/envs/env.ENV.yaml for list of available variables
locals {
  env = yamldecode(file("../Core/sensitive/envs/${split("_", terraform.workspace)[1]}/env.${split("_", terraform.workspace)[0]}.yaml"))
}

provider "aws" {
  region                  = local.env.region
  profile                 = local.env.environment
  shared_credentials_files = ["/cloud/aws/credentials"]

  default_tags {
    tags = merge(local.env.tags, {
      CreatedBy = "Terraform"
      # s
    })
  }
}

data "terraform_remote_state" "core" {
  backend = "s3"

  config = {
    bucket                  = "hydrovis-terraform-state-us-east-1"
    key                     = "state"
    region                  = "us-east-1"
    profile                 = "prod"
    shared_credentials_file = "/cloud/aws/credentials"
  }
  workspace = terraform.workspace
}

module "builder-security-group" {
  source = "./BuilderSecurityGroup"

  vpc_main_cidr_block = local.env.vpc_ip_block
  vpc_main_id         = data.terraform_remote_state.core.outputs.vpc_main.id
}

module "builder-iam-role" {
  source   = "./BuilderIAMRole"

  environment = local.env.environment
  region      = local.env.region

  session_manager_logs_bucket_arn = data.terraform_remote_state.core.outputs.bucket_session-manager-logs.arn
  session_manager_logs_kms_arn     = data.terraform_remote_state.core.outputs.key_session-manager-logs.arn
  rnr_bucket_arn                 = data.terraform_remote_state.core.outputs.bucket_rnr.arn
  rnr_kms_arn                      = data.terraform_remote_state.core.outputs.key_rnr.arn
}

module "artifact-bucket" {
  source = "./ArtifactBucket"

  account_id  = local.env.account_id
  region      = local.env.region

  builder_role_arn = module.builder-iam-role.role.arn
  admin_team_arns  = local.env.admin_team_arns
}

module "pipelines" {
  source   = "./Pipelines"

  environment = local.env.environment
  region      = local.env.region

  artifact_bucket_name               = module.artifact-bucket.bucket
  builder_role_instance_profile_name = module.builder-iam-role.profile.name
  builder_sg_id                      = module.builder-security-group.id
  builder_subnet_id                  = data.terraform_remote_state.core.outputs.subnet_data1b.id
  ami_sharing_account_ids            = [
    local.env.uat_account_id,
    local.env.prod_account_id
  ]
}