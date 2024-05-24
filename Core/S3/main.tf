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

variable "buckets_and_bucket_users" {
  type = map(list(string))
}


resource "aws_s3_account_public_access_block" "main" {
  block_public_acls   = true
  block_public_policy = true
}

module "bucket" {
  source   = "./bucket"
  for_each = var.buckets_and_bucket_users

  environment = var.environment
  account_id  = var.account_id
  region      = var.region

  name                  = each.key
  access_principal_arns = compact(each.value)
  admin_team_arns       = var.admin_team_arns
}

output "buckets" {
  value = { for bucket_short_name in keys(var.buckets_and_bucket_users) : bucket_short_name => module.bucket[bucket_short_name].bucket }
}

output "keys" {
  value = { for bucket_short_name in keys(var.buckets_and_bucket_users) : bucket_short_name => module.bucket[bucket_short_name].key }
}