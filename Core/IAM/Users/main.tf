variable "environment" {
  type = string
}

variable "account_id" {
  type = string
}

variable "region" {
  type = string
}

# S3 Replication Incoming Data Service Account
resource "aws_iam_user" "S3ReplicationDataServiceAccount" {
  count = var.environment == "prod" ? 1 : 0

  name = "hydrovis-data-prod-ingest-service-user_${var.region}"
}

resource "aws_iam_user_policy" "S3ReplicationDataServiceAccount" {
  count = var.environment == "prod" ? 1 : 0
  
  name = "hydrovis-data-prod-ingest-service-user_${var.region}"
  user = aws_iam_user.S3ReplicationDataServiceAccount[0].name

  policy = templatefile("${path.module}/s3-replication-data-service-account-policy.json.tftpl", {
    region = var.region
  })
}

resource "aws_iam_access_key" "S3ReplicationDataServiceAccount" {
  count = var.environment == "prod" ? 1 : 0
  
  user = aws_iam_user.S3ReplicationDataServiceAccount[0].name
}

resource "local_file" "S3ReplicationDataServiceAccount" {
  count = var.environment == "prod" ? 1 : 0
  
  content  = "ID: ${aws_iam_access_key.S3ReplicationDataServiceAccount[0].id}\nSecret: ${aws_iam_access_key.S3ReplicationDataServiceAccount[0].secret}"
  filename = "${path.root}/sensitive/Certs/${aws_iam_user.S3ReplicationDataServiceAccount[0].name}-${var.environment}"
}


# WRDS Service Account
resource "aws_iam_user" "WRDSServiceAccount" {
  name = "wrds-service-account_${var.region}"
}

resource "aws_iam_user_policy" "WRDSServiceAccount" {
  name = "wrds-service-account_${var.region}"
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
  name = "fim-service-account_${var.region}"
}

resource "aws_iam_user_policy" "FIMServiceAccount" {
  name = "fim-service-account_${var.region}"
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
  name = "ised-service-account_${var.region}"
}

resource "aws_iam_user_policy" "ISEDServiceAccount" {
  name = "ised-service-account_${var.region}"
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

output "user_S3ReplicationDataServiceAccount" {
  value = var.environment == "prod" ? aws_iam_user.S3ReplicationDataServiceAccount[0] : aws_iam_user.WRDSServiceAccount
}

output "user_FIMServiceAccount" {
  value = aws_iam_user.FIMServiceAccount
}

output "user_ISEDServiceAccount" {
  value = aws_iam_user.ISEDServiceAccount
}