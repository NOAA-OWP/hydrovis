variable "environment" {
  type = string
}

variable "account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "admin_team_arns" {
  type = list(string)
}

variable "role_HydrovisESRISSMDeploy_arn" {
  type = string
}

variable "role_autoscaling_arn" {
  type = string
}


locals {
  buckets_and_bucket_users = {
    "none" = {
      "access_principal_arns" = [
        var.role_autoscaling_arn,
        var.role_HydrovisESRISSMDeploy_arn
      ]
      "policy_filename" = "standard.json.tftpl"
    }
    "gis-server-cache" = {
      "access_principal_arns" = [
        var.role_autoscaling_arn,
        var.role_HydrovisESRISSMDeploy_arn
      ]
      "policy_filename" = "standard.json.tftpl"
    }
    "gp-server-cache" = {
      "access_principal_arns" = [
        var.role_autoscaling_arn,
        var.role_HydrovisESRISSMDeploy_arn
      ]
      "policy_filename" = "standard.json.tftpl"
    }
    "img-server-cache" = {
      "access_principal_arns" = [
        var.role_autoscaling_arn,
        var.role_HydrovisESRISSMDeploy_arn
      ]
      "policy_filename" = "standard.json.tftpl"
    }
    "prv-alb-logging" = {
      "access_principal_arns" = [
        var.role_autoscaling_arn,
        var.role_HydrovisESRISSMDeploy_arn
      ]
      "policy_filename" = "standard.json.tftpl"
    }
    "ptl-content" = {
      "access_principal_arns" = [
        var.role_autoscaling_arn,
        var.role_HydrovisESRISSMDeploy_arn
      ]
      "policy_filename" = "portalcontent_S3_bucket_policy.json"
    }
    "pub-alb-logging" = {
      "access_principal_arns" = [
        var.role_autoscaling_arn,
        var.role_HydrovisESRISSMDeploy_arn
      ]
      "policy_filename" = "standard.json.tftpl"
    }
    "webgisdr" = {
      "access_principal_arns" = [
        var.role_autoscaling_arn,
        var.role_HydrovisESRISSMDeploy_arn
      ]
      "policy_filename" = "webgisdr_S3_bucket_policy.json"
    }
  }
}

module "bucket" {
  source   = "./bucket"
  for_each = local.buckets_and_bucket_users

  environment = var.environment
  account_id  = var.account_id
  region      = var.region

  name_suffix           = each.key
  access_principal_arns = each.value["access_principal_arns"]
  policy_filename       = each.value["policy_filename"]
  admin_team_arns       = var.admin_team_arns
}

output "buckets" {
  value = { for bucket_short_name in keys(local.buckets_and_bucket_users) : bucket_short_name => module.bucket[bucket_short_name].bucket }
}