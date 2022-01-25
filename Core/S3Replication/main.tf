variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "account_id" {
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

locals {
  buckets_and_bucket_users = {
    "hml" = {
      replication_role_arn = "arn:aws:iam::${var.prod_account_id}:role/hydrovis-prod-hml-incoming-s3st-HMLReplicationRole-1INFV8WNQTTHE"
      access_principal_arns = [
        var.user_data-ingest-service-user_arn
      ]
    }
    "nwm" = {
      replication_role_arn = "arn:aws:iam::${var.prod_account_id}:role/hydrovis-prod-nwm-incoming-s3st-NWMReplicationRole-P9EAA8EI6VNC"
      access_principal_arns = [
        var.role_hydrovis-viz-proc-pipeline-lambda_arn
      ]
    }
    "pcpanl" = {
      replication_role_arn = "arn:aws:iam::${var.prod_account_id}:role/hydrovis-prod-pcpanl-incoming-replication"
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
  replication_role_arn  = each.value["replication_role_arn"]
  access_principal_arns = each.value["access_principal_arns"]
  prod_account_id       = var.prod_account_id
  admin_team_arns       = var.admin_team_arns
}

output "buckets" {
  value = { for bucket_short_name in keys(local.buckets_and_bucket_users) : bucket_short_name => module.bucket[bucket_short_name].bucket }
}