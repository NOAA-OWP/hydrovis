variable "environment" {
  type = string
}

variable "name" {
  type = string
}

variable "username" {
  type = string
}

variable "password" {
  type = string
}

resource "aws_secretsmanager_secret" "hydrovis" {
  description             = "hv-vpp-${var.environment}-${var.name}"
  name                    = "hv-vpp-${var.environment}-${var.name}"
  recovery_window_in_days = 0
}

resource "random_password" "password" {
  length  = 25
  special = false
}

resource "aws_secretsmanager_secret_version" "hydrovis" {
  secret_id = aws_secretsmanager_secret.hydrovis.arn
  secret_string = jsonencode({
    "username" = var.username
    "password" = var.password != "" ? var.password : random_password.password.result
  })
}

output "secret_string" {
  value = aws_secretsmanager_secret_version.hydrovis.secret_string
}

output "secret_arn" {
  value = aws_secretsmanager_secret.hydrovis.arn
}