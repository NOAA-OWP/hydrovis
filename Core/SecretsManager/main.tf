variable "environment" {
  type = string
}

variable "names_and_users" {
  type = map(map(string))
}

module "secret" {
  source      = "./secret"
  for_each    = var.names_and_users
  environment = var.environment
  name        = each.key
  username    = each.value["username"]
  password    = contains(keys(each.value), "password") ? each.value["password"] : ""
}

output "secret_strings" {
  value = { for name in keys(var.names_and_users) : name => module.secret[name].secret_string }
}

output "secret_arns" {
  value = { for name in keys(var.names_and_users) : name => module.secret[name].secret_arn }
}