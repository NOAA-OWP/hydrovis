variable "environment" {
  type = string
}

variable "account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "uat_account_id" {
  type = string
}

variable "prod_account_id" {
  type = string
}

variable "vpc_ip_block" {
  type = string
}

variable "vpc_main_id" {
  type = string
}

variable "admin_team_arns" {
  type = list(string)
}

variable "session_manager_logs_bucket_arn" {
  type = string
}

variable "session_manager_logs_kms_arn" {
  type = string
}

variable "rnr_bucket_arn" {
  type = string
}

variable "rnr_kms_arn" {
  type = string
}

variable "builder_subnet_id" {
  type = string
}


module "builder-security-group" {
  source = "./BuilderSecurityGroup"

  vpc_main_cidr_block = var.vpc_ip_block
  vpc_main_id         = var.vpc_main_id
}

module "builder-iam-role" {
  source   = "./BuilderIAMRole"

  environment = var.environment
  region      = var.region

  session_manager_logs_bucket_arn = var.session_manager_logs_bucket_arn
  session_manager_logs_kms_arn    = var.session_manager_logs_kms_arn
  rnr_bucket_arn                  = var.rnr_bucket_arn
  rnr_kms_arn                     = var.rnr_kms_arn
}

module "artifact-bucket" {
  source = "./ArtifactBucket"

  account_id  = var.account_id
  region      = var.region

  builder_role_arn = module.builder-iam-role.role.arn
  admin_team_arns  = var.admin_team_arns
}

module "pipelines" {
  source   = "./Pipelines"

  environment = var.environment
  region      = var.region

  artifact_bucket_name               = module.artifact-bucket.bucket
  builder_role_instance_profile_name = module.builder-iam-role.profile.name
  builder_sg_id                      = module.builder-security-group.id
  builder_subnet_id                  = var.builder_subnet_id
  ami_sharing_account_ids            = [
    var.uat_account_id,
    var.prod_account_id
  ]
}