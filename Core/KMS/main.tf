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

variable "keys_and_key_users" {
  type = map(list(string))
}

module "key" {
  source   = "./key"
  for_each = var.keys_and_key_users

  environment = var.environment
  account_id  = var.account_id
  region      = var.region

  name                  = each.key
  access_principal_arns = each.value
  admin_team_arns       = var.admin_team_arns
}

output "key_arns" {
  value = { for short_name in keys(var.keys_and_key_users) : short_name => module.key[short_name].arn }
}