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

variable "replication_role_arn" {
  type = string
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
            AWS = concat(var.admin_team_arns, concat(var.access_principal_arns, [var.replication_role_arn]))
          }
          Resource = "*"
          Sid      = "Allow use of the key"
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

  lifecycle_rule {
    abort_incomplete_multipart_upload_days = 0
    enabled                                = true

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      days = 1
    }
  }

  server_side_encryption_configuration {
    rule {
      bucket_key_enabled = true

      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.hydrovis-s3.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  versioning {
    enabled = true
  }
}

resource "aws_s3_bucket_policy" "hydrovis" {
  bucket = aws_s3_bucket.hydrovis.id
  policy = jsonencode(
    {
      Version = "2008-10-17"
      Statement = [
        {
          Action = "s3:PutObject"
          Condition = {
            StringNotEquals = {
              "s3:x-amz-server-side-encryption" = "aws:kms"
            }
          }
          Effect    = "Deny"
          Principal = "*"
          Resource  = "${aws_s3_bucket.hydrovis.arn}/*"
          Sid       = "DenyUnEncryptedObjectUploads"
        },
        {
          Action = [
            "s3:ReplicateDelete",
            "s3:ReplicateObject",
          ]
          Effect = "Allow"
          Principal = {
            AWS = var.replication_role_arn
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
            AWS = var.replication_role_arn
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