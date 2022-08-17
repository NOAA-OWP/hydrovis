variable "environment" {
  type = string
}

variable "account_id" {
  type = string
}

variable "region" {
  type = string
}

# WRDS Service Account
resource "aws_iam_user" "WRDSServiceAccount" {
  name = "wrds-service-account"
}

resource "aws_iam_user_policy" "WRDSServiceAccount" {
  name = "wrds-service-account"
  user = aws_iam_user.WRDSServiceAccount.name

  policy = templatefile("${path.module}/wrds-service-account-policy.json.tftpl", {})
}

resource "aws_iam_access_key" "WRDSServiceAccount" {
  user = aws_iam_user.WRDSServiceAccount.name
}

resource "local_file" "WRDSServiceAccount" {
  content  = "ID: ${aws_iam_access_key.WRDSServiceAccount.id}\nSecret: ${aws_iam_access_key.WRDSServiceAccount.secret}"
  filename = "${path.root}/sensitive/Certs/${aws_iam_user.WRDSServiceAccount.name}-${var.environment}"
}


# FIM Service Account
resource "aws_iam_user" "FIMServiceAccount" {
  name = "fim-service-account"
}

resource "aws_iam_user_policy" "FIMServiceAccount" {
  name = "fim-service-account"
  user = aws_iam_user.FIMServiceAccount.name

  policy = templatefile("${path.module}/fim-service-account-policy.json.tftpl", {})
}

resource "aws_iam_access_key" "FIMServiceAccount" {
  user = aws_iam_user.FIMServiceAccount.name
}

resource "local_file" "FIMServiceAccount" {
  content  = "ID: ${aws_iam_access_key.FIMServiceAccount.id}\nSecret: ${aws_iam_access_key.FIMServiceAccount.secret}"
  filename = "${path.root}/sensitive/Certs/${aws_iam_user.FIMServiceAccount.name}-${var.environment}"
}


# ISED Service Account
resource "aws_iam_user" "ISEDServiceAccount" {
  name = "ised-service-account"
}

resource "aws_iam_user_policy" "ISEDServiceAccount" {
  name = "ised-service-account"
  user = aws_iam_user.ISEDServiceAccount.name

  policy = templatefile("${path.module}/ised-service-account-policy.json.tftpl", {})
}

resource "aws_iam_access_key" "ISEDServiceAccount" {
  user = aws_iam_user.ISEDServiceAccount.name
}

resource "local_file" "ISEDServiceAccount" {
  content  = "ID: ${aws_iam_access_key.ISEDServiceAccount.id}\nSecret: ${aws_iam_access_key.ISEDServiceAccount.secret}"
  filename = "${path.root}/sensitive/Certs/${aws_iam_user.ISEDServiceAccount.name}-${var.environment}"
}


output "user_WRDSServiceAccount" {
  value = aws_iam_user.WRDSServiceAccount
}

output "user_FIMServiceAccount" {
  value = aws_iam_user.FIMServiceAccount
}

output "user_ISEDServiceAccount" {
  value = aws_iam_user.ISEDServiceAccount
}