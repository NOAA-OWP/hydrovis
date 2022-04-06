variable "environment" {
  type = string
}

variable "account_id" {
  type = string
}

variable "region" {
  type = string
}


# HydrovisESRISSMDeploy Role
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


output "user_WRDSServiceAccount" {
  value = aws_iam_user.WRDSServiceAccount
}