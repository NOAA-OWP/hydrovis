variable "account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "builder_role_arn" {
  type = string
}

variable "admin_team_arns" {
  type = list(string)
}


resource "aws_kms_key" "hydrovis-s3" {
  description         = "Used for hydrovis-imagebuilder-artifacts-${var.region} bucket encryption"
  enable_key_rotation = true
  policy = jsonencode(
    {
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
            AWS = "*"
          }
          Resource  = "*"
          Condition = {
            "StringEquals" = {
              "kms:ViaService" = "s3.${var.region}.amazonaws.com"
              "kms:CallerAccount" = var.account_id
            }
          }
          Sid = "Allow use of the key"
        }
      ]
      Version = "2012-10-17"
    }
  )
}

resource "aws_kms_alias" "hydrovis-s3" {
  name          = "alias/hydrovis-imagebuilder-artifacts-${var.region}-s3"
  target_key_id = aws_kms_key.hydrovis-s3.key_id
}

resource "aws_s3_bucket" "hydrovis" {
  bucket = "hydrovis-imagebuilder-artifacts-${var.region}"
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

resource "aws_s3_bucket_ownership_controls" "hydrovis" {
  bucket = aws_s3_bucket.hydrovis.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_policy" "hydrovis" {
  bucket = aws_s3_bucket.hydrovis.bucket
  policy = jsonencode(
    {
      Statement = [
        {
          Action = [
            "s3:GetBucketPolicy",
            "s3:GetBucketAcl",
            "s3:GetObject",
            "s3:PutObject",
            "s3:DeleteObject",
            "s3:ListBucket",
          ]
          Effect = "Allow"
          Principal = {
            AWS     = var.builder_role_arn
            Service = "imagebuilder.amazonaws.com"
          }
          Resource = [
            "${aws_s3_bucket.hydrovis.arn}/*",
            "${aws_s3_bucket.hydrovis.arn}",
          ]
        },
      ]
      Version = "2008-10-17"
    }
  )
}

output "bucket" {
  value = aws_s3_bucket.hydrovis.bucket
}