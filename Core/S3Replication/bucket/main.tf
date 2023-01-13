variable "name" {
  type = string
}

variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "prod_account_id" {
  type = string
}

variable "admin_team_arns" {
  type = list(string)
}

variable "access_principal_arns" {
  type = list(string)
}


resource "aws_kms_key" "hydrovis-s3" {
  description         = "Used for hydrovis-${var.environment}-${var.name}-${var.region} bucket encryption"
  enable_key_rotation = true
  policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Action = "kms:*"
          Effect = "Allow"
          Principal = {
            AWS = concat(var.admin_team_arns, ["arn:aws:iam::${var.account_id}:root"])
          }
          Resource = "*"
          Sid      = "Enable IAM User Permissions"
        },
        {
          Action = [
            "kms:Create*",
            "kms:Describe*",
            "kms:Enable*",
            "kms:List*",
            "kms:Put*",
            "kms:Update*",
            "kms:Revoke*",
            "kms:Disable*",
            "kms:Get*",
            "kms:Delete*",
            "kms:ScheduleKeyDeletion",
            "kms:CancelKeyDeletion"
          ]
          Effect = "Allow"
          Principal = {
            AWS = var.admin_team_arns
          }
          Resource = "*"
          Sid      = "Allow administration of the key"
        },
        {
          Action = [
            "kms:DescribeKey",
            "kms:Encrypt",
            "kms:Decrypt",
            "kms:ReEncrypt*",
            "kms:GenerateDataKey",
            "kms:GenerateDataKeyWithoutPlaintext"
          ]
          Effect = "Allow"
          Principal = {
            AWS = concat(var.admin_team_arns, var.access_principal_arns)
          }
          Resource = "*"
          Sid      = "Allow use of the key"
        },
        {
          Action = [
            "kms:DescribeKey",
            "kms:Encrypt",
            "kms:Decrypt",
            "kms:ReEncrypt*",
            "kms:GenerateDataKey",
            "kms:GenerateDataKeyWithoutPlaintext"
          ]
          Effect = "Allow"
          Principal = {
            AWS = var.prod_account_id
          }
          Condition = {
            "StringEqualsIfExists" = {
              "aws:PrincipalArn" = "arn:aws:iam::${var.prod_account_id}:role/hydrovis-prod-${var.name}-replication-${var.region}"
            }
          }
          Resource = "*"
          Sid      = "Allow use of the key for replication"
        },
      ]
    }
  )
}

resource "aws_kms_alias" "hydrovis-s3" {
  name          = "alias/hydrovis-${var.environment}-${var.name}-${var.region}-s3"
  target_key_id = aws_kms_key.hydrovis-s3.key_id
}

resource "aws_s3_bucket" "hydrovis" {
  bucket = "hydrovis-${var.environment}-${var.name}-${var.region}"
}

resource "aws_s3_bucket_lifecycle_configuration" "hydrovis" {
  bucket = aws_s3_bucket.hydrovis.id

  rule {
    id     = "30 Day Expiration"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "hydrovis" {
  bucket = aws_s3_bucket.hydrovis.bucket

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.hydrovis-s3.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_versioning" "hydrovis" {
  bucket = aws_s3_bucket.hydrovis.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "hydrovis" {
  bucket = aws_s3_bucket.hydrovis.id
  policy = jsonencode(
    {
      Version = "2008-10-17"
      Statement = [
        {
          Action = [
            "s3:ReplicateDelete",
            "s3:ReplicateObject",
          ]
          Effect = "Allow"
          Principal = {
            AWS = var.prod_account_id
          }
          Condition = {
            "StringEqualsIfExists" = {
              "aws:PrincipalArn" = "arn:aws:iam::${var.prod_account_id}:role/hydrovis-prod-${var.name}-replication-${var.region}"
            }
          }
          Resource = "${aws_s3_bucket.hydrovis.arn}/*"
          Sid      = "PermissionsOnObjects"
        },
        {
          Action = [
            "s3:List*",
            "s3:GetBucketVersioning",
            "s3:PutBucketVersioning",
          ]
          Effect = "Allow"
          Principal = {
            AWS = var.prod_account_id
          }
          Condition = {
            "StringEqualsIfExists" = {
              "aws:PrincipalArn" = "arn:aws:iam::${var.prod_account_id}:role/hydrovis-prod-${var.name}-replication-${var.region}"
            }
          }
          Resource = aws_s3_bucket.hydrovis.arn
          Sid      = "PermissionsOnBucket"
        },
        {
          Action = "s3:ObjectOwnerOverrideToBucketOwner"
          Effect = "Allow"
          Principal = {
            AWS = "arn:aws:iam::${var.prod_account_id}:root"
          }
          Resource = "${aws_s3_bucket.hydrovis.arn}/*"
          Sid      = "OverrideBucketOwner"
        },
        {
          Action = [
            "s3:GetBucketPolicy",
            "s3:GetBucketAcl",
            "s3:GetObject",
            "s3:PutObject",
            "s3:ListBucket",
          ]
          Effect = "Allow"
          Principal = {
            AWS = concat(var.admin_team_arns, var.access_principal_arns)
          }
          Resource = [
            aws_s3_bucket.hydrovis.arn,
            "${aws_s3_bucket.hydrovis.arn}/*",
          ]
          Sid = "PermissionsOnObjectsToUsersRoles"
        },
      ]
    }
  )
}

output "bucket" {
  value = aws_s3_bucket.hydrovis
}