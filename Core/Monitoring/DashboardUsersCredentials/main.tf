variable "environment" {
  type = string
}

variable "username" {
  type = string
}

resource "aws_secretsmanager_secret" "hydrovis" {
  description             = "hydrovis-${var.environment}-opensearch-${var.username}"
  name                    = "hydrovis-${var.environment}-opensearch-${var.username}"
  recovery_window_in_days = 0
}

resource "random_password" "password" {
  length           = 25
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "-_"
}

resource "aws_secretsmanager_secret_version" "hydrovis" {
  secret_id = aws_secretsmanager_secret.hydrovis.arn
  secret_string = jsonencode({
    "username" = var.username
    "password" = random_password.password.result
  })
}

output "secret_string" {
  value = aws_secretsmanager_secret_version.hydrovis.secret_string
}
