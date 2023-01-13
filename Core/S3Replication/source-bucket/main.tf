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

variable "source_access_user_name" {
  type = string
}

variable "ti_account_id" {
  type = string
}

variable "uat_account_id" {
  type = string
}

variable "prod_account_id" {
  type = string
}

variable "admin_team_arns" {
  type = list(string)
}

resource "aws_kms_key" "hydrovis" {
  description         = "KMS Key for ${upper(var.name)} Incoming Bucket"
  enable_key_rotation = true
  policy = jsonencode(
    {
      Version = "2012-10-17"
      Id      = "hydrovis-${var.environment}-${var.name}-${var.region}-s3-policy"
      Statement = [
        {
          Action = "kms:*"
          Effect = "Allow"
          Principal = {
            AWS = [
              "arn:aws:iam::${var.prod_account_id}:root",
            ]
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
          ]
          Effect = "Allow"
          Principal = {
            AWS = concat(var.admin_team_arns, [
              "arn:aws:iam::${var.prod_account_id}:user/${var.source_access_user_name}",
              "arn:aws:iam::${var.prod_account_id}:role/hydrovis-prod-${var.name}-replication-${var.region}",
            ])
          }
          Resource = "*"
          Sid      = "Allow use of the key"
        },
      ]
    }
  )
}

resource "aws_kms_alias" "hydrovis" {
  name          = "alias/hydrovis-${var.environment}-${var.name}-${var.region}-s3"
  target_key_id = aws_kms_key.hydrovis.key_id
}

resource "aws_iam_role" "hydrovis" {
  name  = "hydrovis-prod-${var.name}-replication-${var.region}"
  assume_role_policy = jsonencode(
    {
      Version = "2008-10-17"
      Statement = [
        {
          Action = "sts:AssumeRole"
          Effect = "Allow"
          Principal = {
            Service = "s3.amazonaws.com"
          }
        },
      ]

    }
  )

  inline_policy {
    name   = "${upper(var.name)}BucketReplicationPolicy"
    policy = jsonencode(
      {
        Version = "2012-10-17"
        Statement = [
          {
            Action   = "iam:PassRole"
            Effect   = "Allow"
            Resource = "arn:aws:iam::${var.prod_account_id}:role/hydrovis-prod-${var.name}-replication-${var.region}"
            Sid      = "VisualEditor4"
          },
          {
            Action = [
              "s3:GetObjectVersionTagging",
              "s3:GetObjectVersionAcl",
              "s3:GetObjectVersion",
              "s3:GetObjectVersionForReplication",
              "s3:ListBucket",
              "s3:GetBucketVersioning",
              "s3:GetReplicationConfiguration",
            ]
            Effect = "Allow"
            Resource = [
              "arn:aws:s3:::hydrovis-prod-${var.name}-incoming-${var.region}/*",
              "arn:aws:s3:::hydrovis-prod-${var.name}-incoming-${var.region}",
            ]
            Sid = "VisualEditor8"
          },
          {
            Action = "kms:Decrypt"
            Condition = {
              StringLike = {
                "kms:ViaService" = "s3.${var.region}.amazonaws.com"
              }
            }
            Effect   = "Allow"
            Resource = aws_kms_key.hydrovis.arn
            Sid      = "VisualEditor0"
          },
          {
            Action = "kms:Encrypt"
            Condition = {
              "ForAnyValue:StringLike" = {
                "kms:ResourceAliases" = "alias/hydrovis-*-${var.name}-*"
              }
              StringLike = {
                "kms:ViaService" = "s3.${var.region}.amazonaws.com"
              }
            }
            Effect   = "Allow"
            Resource = "*"
            Sid      = "VisualEditor3"
          },
          {
            Action = [
              "s3:ObjectOwnerOverrideToBucketOwner",
              "s3:ReplicateObject",
              "s3:ReplicateTags",
              "s3:ReplicateDelete",
            ]
            Effect = "Allow"
            Resource = [
              "arn:aws:s3:::hydrovis-*-${var.name}-*",
              "arn:aws:s3:::hydrovis-*-${var.name}-*/*",
            ]
            Sid = "VisualEditor5"
          },
        ]
      }
    )
  }
}

resource "aws_s3_bucket" "hydrovis" {
  bucket = "hydrovis-prod-${var.name}-incoming-${var.region}"
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

resource "aws_s3_bucket_replication_configuration" "hydrovis" {
  bucket = aws_s3_bucket.hydrovis.id
  role   = aws_iam_role.hydrovis.arn

  rule {
    id       = "${upper(var.name)}ReplicationRoleToProd${upper(var.name)}"
    priority = 0
    status   = "Enabled"

    filter {}

    delete_marker_replication {
      status = "Disabled"
    }

    destination {
      bucket = "arn:aws:s3:::hydrovis-prod-${var.name}-${var.region}"

      encryption_configuration {
        replica_kms_key_id = "arn:aws:kms:${var.region}:${var.prod_account_id}:alias/hydrovis-prod-${var.name}-${var.region}-s3"
      }
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
  }

  rule {
    id       = "${upper(var.name)}ReplicationRoleToUat${upper(var.name)}"
    priority = 1
    status   = "Enabled"
        
    filter {}

    delete_marker_replication {
      status = "Disabled"
    }

    destination {
      account = "${var.uat_account_id}"
      bucket     = "arn:aws:s3:::hydrovis-uat-${var.name}-${var.region}"

      encryption_configuration {
        replica_kms_key_id = "arn:aws:kms:${var.region}:${var.uat_account_id}:alias/hydrovis-uat-${var.name}-${var.region}-s3"
      }

      access_control_translation {
        owner = "Destination"
      }
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
  }

  # Only create Ti replication rule for regions that have a Ti environment
  dynamic rule {
    for_each = var.ti_account_id != "" ? [1] : []

    content {
      id       = "${upper(var.name)}ReplicationRoleToTi${upper(var.name)}"
      priority = 2
      status   = "Enabled"
          
      filter {}

      delete_marker_replication {
        status = "Disabled"
      }

      destination {
        account = "${var.ti_account_id}"
        bucket     = "arn:aws:s3:::hydrovis-ti-${var.name}-${var.region}"

        encryption_configuration {
          replica_kms_key_id = "arn:aws:kms:${var.region}:${var.ti_account_id}:alias/hydrovis-ti-${var.name}-${var.region}-s3"
        }

        access_control_translation {
          owner = "Destination"
        }
      }

      source_selection_criteria {
        sse_kms_encrypted_objects {
          status = "Enabled"
        }
      }
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "hydrovis" {
  bucket = aws_s3_bucket.hydrovis.bucket

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.hydrovis.arn
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