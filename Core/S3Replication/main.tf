variable "environment" {
  type = string
}

variable "region" {
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

variable "admin_team_arns" {
  type = list(string)
}

variable "user_S3ReplicationDataServiceAccount_arn" {
  type = string
}

variable "user_data-ingest-service-user_arn" {
  type = string
}

variable "role_viz_pipeline_arn" {
  type = string
}

variable "role_rnr_arn" {
  type = string
}

locals {
  buckets_and_bucket_users = {
    "hml" = {
      access_principal_arns = [
        var.user_data-ingest-service-user_arn,
        "arn:aws:iam::${var.prod_account_id}:role/hydrovis-prod-hml-incoming-s3st-HMLReplicationRole-1INFV8WNQTTHE"
      ]
    }
    "nwm" = {
      access_principal_arns = [
        var.role_viz_pipeline_arn,
        var.role_rnr_arn,
        "arn:aws:iam::${var.prod_account_id}:role/hydrovis-prod-nwm-incoming-s3st-NWMReplicationRole-P9EAA8EI6VNC"
      ]
    }
    "pcpanl" = {
      access_principal_arns = [
        var.user_data-ingest-service-user_arn
      ]
    }
  }
}

module "bucket" {
  source   = "./bucket"
  for_each = local.buckets_and_bucket_users

  environment = var.environment
  account_id  = var.account_id
  region      = var.region

  name                  = each.key
  access_principal_arns = each.value["access_principal_arns"]
  prod_account_id       = var.prod_account_id
  admin_team_arns       = var.admin_team_arns
}

module "source-bucket" {
  source   = "./source-bucket"
  for_each = var.environment == "prod" ? local.buckets_and_bucket_users : {} // This makes sure this is only built when deploying to prod

  environment = var.environment
  account_id  = var.account_id
  region      = var.region

  name                       = each.key
  source_service_account_arn = var.user_S3ReplicationDataServiceAccount_arn
  ti_account_id              = var.ti_account_id
  uat_account_id             = var.uat_account_id
  prod_account_id            = var.prod_account_id
  admin_team_arns            = var.admin_team_arns
}

output "buckets" {
  value = { for bucket_short_name in keys(local.buckets_and_bucket_users) : bucket_short_name => module.bucket[bucket_short_name].bucket }
}