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

variable "user_data-ingest-service-user_arn" {
  type = string
}

variable "role_hydrovis-viz-proc-pipeline-lambda_arn" {
  type = string
}

variable "role_Hydroviz-RnR-EC2-Profile_arn" {
  type = string
}

locals {
  buckets_and_bucket_users = {
    "hml" = {
      replication_role_name = "hydrovis-prod-hml-incoming-s3st-HMLReplicationRole-1INFV8WNQTTHE"
      source_access_user_name = "hydrovis-data-prod-ingest-service-user"
      access_principal_arns = [
        var.user_data-ingest-service-user_arn
      ]
    }
    "nwm" = {
      replication_role_name = "hydrovis-prod-nwm-incoming-s3st-NWMReplicationRole-P9EAA8EI6VNC"
      source_access_user_name = "hydrovis-data-prod-ingest-service-user"
      access_principal_arns = [
        var.role_hydrovis-viz-proc-pipeline-lambda_arn,
        var.role_Hydroviz-RnR-EC2-Profile_arn
      ]
    }
    "pcpanl" = {
      replication_role_name = "hydrovis-prod-pcpanl-incoming-replication"
      source_access_user_name = "hydrovis-data-prod-ingest-service-user"
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
  replication_role_name = each.value["replication_role_name"]
  access_principal_arns = each.value["access_principal_arns"]
  prod_account_id       = var.prod_account_id
  admin_team_arns       = var.admin_team_arns
}

# module "source-bucket" {
#   source   = "./source-bucket"
#   for_each = var.environment == "prod" ? local.buckets_and_bucket_users : {} // This makes sure this is only built when deploying to prod

#   environment = var.environment
#   account_id  = var.account_id
#   region      = var.region

#   name                    = each.key
#   replication_role_name   = each.value["replication_role_name"]
#   source_access_user_name = each.value["source_access_user_name"]
#   ti_account_id           = var.ti_account_id
#   uat_account_id          = var.uat_account_id
#   prod_account_id         = var.prod_account_id
#   admin_team_arns         = var.admin_team_arns
# }

output "buckets" {
  value = { for bucket_short_name in keys(local.buckets_and_bucket_users) : bucket_short_name => module.bucket[bucket_short_name].bucket }
}