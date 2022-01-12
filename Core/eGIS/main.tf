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
    "none" = [
      var.role_autoscaling_arn,
      var.role_HydrovisESRISSMDeploy_arn
    ]
    "gis-server-cache" = [
      var.role_autoscaling_arn,
      var.role_HydrovisESRISSMDeploy_arn
    ]
    "gp-server-cache" = [
      var.role_autoscaling_arn,
      var.role_HydrovisESRISSMDeploy_arn
    ]
    "img-server-cache" = [
      var.role_autoscaling_arn,
      var.role_HydrovisESRISSMDeploy_arn
    ]
    "prv-alb-logging" = [
      var.role_autoscaling_arn,
      var.role_HydrovisESRISSMDeploy_arn
    ]
    "ptl-content" = [
      var.role_autoscaling_arn,
      var.role_HydrovisESRISSMDeploy_arn
    ]
    "pub-alb-logging" = [
      var.role_autoscaling_arn,
      var.role_HydrovisESRISSMDeploy_arn
    ]
    "webgisdr" = [
      var.role_autoscaling_arn,
      var.role_HydrovisESRISSMDeploy_arn
    ]
  }
}

module "bucket" {
  source   = "./bucket"
  for_each = local.buckets_and_bucket_users

  environment = var.environment
  account_id  = var.account_id
  region      = var.region

  name_suffix           = each.key
  access_principal_arns = each.value
  admin_team_arns       = var.admin_team_arns
}

output "buckets" {
  value = { for bucket_short_name in keys(local.buckets_and_bucket_users) : bucket_short_name => module.bucket[bucket_short_name].bucket }
}