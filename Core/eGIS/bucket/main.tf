variable "name_suffix" {
  type = string
}

variable "environment" {
  type = string
}

variable "account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "policy_filename" {
  type = string
}

variable "admin_team_arns" {
  type = list(string)
}

variable "access_principal_arns" {
  type = list(string)
}

resource "aws_kms_key" "hydrovis-s3" {
  description         = "Used for hydrovis-${var.environment}-egis-${var.region}${var.name_suffix != "none" ? format("-%s", var.name_suffix) : ""} bucket encryption"
  enable_key_rotation = true
  policy = jsonencode(
    {
      Statement = concat([
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
            "kms:CancelKeyDeletion",
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
            "kms:GenerateDataKeyWithoutPlaintext",
            "kms:List*",
            "kms:Get*",
            "kms:Describe*",
          ]
          Effect = "Allow"
          Principal = {
            AWS = concat(var.admin_team_arns, var.access_principal_arns)
          }
          Resource = "*"
          Sid      = "Allow use of the key"
        }
        ],
        [ # This is specifically for the buckets that use the autoscaling role
          for arn in var.access_principal_arns : {
            "Sid" : "Allow attachment of persistent resources",
            "Effect" : "Allow",
            "Principal" : {
              "AWS" = arn
            },
            "Action" = "kms:CreateGrant",
            "Resource" : "*",
            "Condition" : {
              "Bool" : {
                "kms:GrantIsForAWSResource" : "true"
              }
            }
          }
          if contains(split("/", arn), "autoscaling.amazonaws.com")
      ])
      Version = "2012-10-17"
    }
  )
}

resource "aws_kms_alias" "hydrovis-s3" {
  name          = "alias/hydrovis-${var.environment}-egis-${var.region}${var.name_suffix != "none" ? format("-%s", var.name_suffix) : ""}-s3"
  target_key_id = aws_kms_key.hydrovis-s3.key_id
}

resource "aws_s3_bucket" "hydrovis" {
  bucket = "hydrovis-${var.environment}-egis-${var.region}${var.name_suffix != "none" ? format("-%s", var.name_suffix) : ""}"

  server_side_encryption_configuration {
    rule {
      bucket_key_enabled = true

      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.hydrovis-s3.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }
}

resource "aws_s3_bucket_policy" "hydrovis" {
  bucket = aws_s3_bucket.hydrovis.bucket
  policy = templatefile("${path.module}/../templates/${var.policy_filename}", {
    bucket_arn            = aws_s3_bucket.hydrovis.arn
    access_principal_arns = jsonencode(concat(var.admin_team_arns, var.access_principal_arns))
    kms_key_arn = aws_kms_key.hydrovis-s3.arn
  })
}

output "bucket" {
  value = aws_s3_bucket.hydrovis
}