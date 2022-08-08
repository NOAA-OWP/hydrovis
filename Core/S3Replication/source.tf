resource "aws_kms_key" "hydrovis-hml-incoming-s3" {
  count               = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  description         = "Symmetric CMK for KMS-KEY-ARN for HML Incoming Bucket"
  enable_key_rotation = true
  policy = jsonencode(
    {
      Version = "2012-10-17"
      Id      = "key-hydrovis-prod-hml-incoming-kms-cmk-policy"
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
              "arn:aws:iam::${var.prod_account_id}:user/hydrovis-data-prod-ingest-service-user",
              "arn:aws:iam::${var.prod_account_id}:role/hydrovis-prod-hml-incoming-s3st-HMLReplicationRole-1INFV8WNQTTHE",
            ])
          }
          Resource = "*"
          Sid      = "Allow use of the key"
        },
      ]
    }
  )
}

resource "aws_kms_alias" "hydrovis-hml-incoming-s3" {
  count = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  name          = "alias/noaa-nws-hydrovis-prod-hml-incoming-s3-cmk-alias"
  target_key_id = aws_kms_key.hydrovis-hml-incoming-s3[0].key_id
}

resource "aws_iam_role" "hml-replication" {
  count = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  name  = "hydrovis-prod-hml-incoming-s3st-HMLReplicationRole-1INFV8WNQTTHE"
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
    name   = "HMLBucketReplicationPolicy"
    policy = jsonencode(
      {
        Version = "2012-10-17"
        Statement = [
          {
            Action   = "iam:PassRole"
            Effect   = "Allow"
            Resource = "arn:aws:iam::${var.prod_account_id}:role/hydrovis-prod-hml-incoming-s3st-HMLReplicationRole-1INFV8WNQTTHE"
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
              "arn:aws:s3:::hydrovis-prod-hml-incoming-us-east-1/*",
              "arn:aws:s3:::hydrovis-prod-hml-incoming-us-east-1",
            ]
            Sid = "VisualEditor8"
          },
          {
            Action = "kms:Decrypt"
            Condition = {
              StringLike = {
                "kms:ViaService" = "s3.us-east-1.amazonaws.com"
              }
            }
            Effect   = "Allow"
            Resource = aws_kms_key.hydrovis-hml-incoming-s3[0].arn
            Sid      = "VisualEditor0"
          },
          {
            Action = "kms:Encrypt"
            Condition = {
              "ForAnyValue:StringLike" = {
                "kms:ResourceAliases" = "alias/hydrovis-*-hml-*"
              }
              StringLike = {
                "kms:ViaService" = "s3.us-east-1.amazonaws.com"
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
              "arn:aws:s3:::hydrovis-*-hml-*",
              "arn:aws:s3:::hydrovis-*-hml-*/*",
            ]
            Sid = "VisualEditor5"
          },
        ]
      }
    )
  }
}

resource "aws_s3_bucket" "hydrovis-hml-incoming" {
  count  = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  bucket = "hydrovis-prod-hml-incoming-us-east-1"
}

resource "aws_s3_bucket_lifecycle_configuration" "hydrovis-hml-incoming" {
  count  = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  bucket = aws_s3_bucket.hydrovis-hml-incoming[0].id

  rule {
    id     = "30 Day Expiration"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 0
    }

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }
}

resource "aws_s3_bucket_replication_configuration" "hydrovis-hml-incoming" {
  count  = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  bucket = aws_s3_bucket.hydrovis-hml-incoming[0].id
  role   = aws_iam_role.hml-replication[0].arn

  rule {
    id       = "HMLReplicationRoleToProdHML"
    priority = 0
    status   = "Enabled"
    filter {}

    destination {
      bucket = "arn:aws:s3:::hydrovis-prod-hml-us-east-1"

      encryption_configuration {
        replica_kms_key_id = "arn:aws:kms:us-east-1:${var.prod_account_id}:alias/hydrovis-prod-hml-us-east-1-s3"
      }
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
  }

  rule {
    id       = "HMLReplicationRoleToUatHML"
    priority = 1
    status   = "Enabled"
    filter {}

    destination {
      account = "${var.uat_account_id}"
      bucket     = "arn:aws:s3:::hydrovis-uat-hml-us-east-1"

      encryption_configuration {
        replica_kms_key_id = "arn:aws:kms:us-east-1:${var.uat_account_id}:alias/hydrovis-uat-hml-us-east-1-s3"
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

  rule {
    id       = "HMLReplicationRoleToTiHML"
    priority = 2
    status   = "Enabled"
    filter {}

    destination {
      account = "${var.ti_account_id}"
      bucket     = "arn:aws:s3:::hydrovis-ti-hml-us-east-1"

      encryption_configuration {
        replica_kms_key_id = "arn:aws:kms:us-east-1:${var.ti_account_id}:alias/hydrovis-ti-hml-us-east-1-s3"
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

resource "aws_s3_bucket_server_side_encryption_configuration" "hydrovis-hml-incoming" {
  count  = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  bucket = aws_s3_bucket.hydrovis-hml-incoming[0].bucket

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.hydrovis-hml-incoming-s3[0].arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_versioning" "hydrovis-hml-incoming" {
  count  = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  bucket = aws_s3_bucket.hydrovis-hml-incoming[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "hydrovis-hml-incoming" {
  count  = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  bucket = aws_s3_bucket.hydrovis-hml-incoming[0].bucket

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
          Resource  = "${aws_s3_bucket.hydrovis-hml-incoming[0].arn}/*"
          Sid       = "DenyUnEncryptedObjectUploads"
        },
      ]
    }
  )
}

























































resource "aws_kms_key" "hydrovis-nwm-incoming-s3" {
  count               = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  description         = "Symmetric CMK for KMS-KEY-ARN for NWM Incoming Bucket"
  enable_key_rotation = true
  policy = jsonencode(
    {
      Version = "2012-10-17"
      Id      = "key-hydrovis-prod-nwm-incoming-kms-cmk-policy"
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
              "arn:aws:iam::${var.prod_account_id}:user/hydrovis-data-prod-ingest-service-user",
              "arn:aws:iam::${var.prod_account_id}:role/hydrovis-prod-nwm-incoming-s3st-NWMReplicationRole-P9EAA8EI6VNC",
            ])
          }
          Resource = "*"
          Sid      = "Allow use of the key"
        },
      ]
    }
  )
}

resource "aws_kms_alias" "hydrovis-nwm-incoming-s3" {
  count = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  name          = "alias/noaa-nws-hydrovis-prod-nwm-incoming-s3-cmk-alias"
  target_key_id = aws_kms_key.hydrovis-nwm-incoming-s3[0].key_id
}

resource "aws_iam_role" "nwm-replication" {
  count = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  name  = "hydrovis-prod-nwm-incoming-s3st-NWMReplicationRole-P9EAA8EI6VNC"
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
    name   = "HMLBucketReplicationPolicy"
    policy = jsonencode(
      {
        Version = "2012-10-17"
        Statement = [
          {
            Action   = "iam:PassRole"
            Effect   = "Allow"
            Resource = "arn:aws:iam::${var.prod_account_id}:role/hydrovis-prod-nwm-incoming-s3st-NWMReplicationRole-P9EAA8EI6VNC"
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
              "arn:aws:s3:::hydrovis-prod-nwm-incoming-us-east-1/*",
              "arn:aws:s3:::hydrovis-prod-nwm-incoming-us-east-1",
            ]
            Sid = "VisualEditor8"
          },
          {
            Action = "kms:Decrypt"
            Condition = {
              StringLike = {
                "kms:ViaService" = "s3.us-east-1.amazonaws.com"
              }
            }
            Effect   = "Allow"
            Resource = aws_kms_key.hydrovis-nwm-incoming-s3[0].arn
            Sid      = "VisualEditor0"
          },
          {
            Action = "kms:Encrypt"
            Condition = {
              "ForAnyValue:StringLike" = {
                "kms:ResourceAliases" = "alias/hydrovis-*-nwm-*"
              }
              StringLike = {
                "kms:ViaService" = "s3.us-east-1.amazonaws.com"
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
              "arn:aws:s3:::hydrovis-*-nwm-*",
              "arn:aws:s3:::hydrovis-*-nwm-*/*",
            ]
            Sid = "VisualEditor5"
          },
        ]
      }
    )
  }
}

resource "aws_s3_bucket" "hydrovis-nwm-incoming" {
  count  = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  bucket = "hydrovis-prod-nwm-incoming-us-east-1"
}

resource "aws_s3_bucket_lifecycle_configuration" "hydrovis-nwm-incoming" {
  count  = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  bucket = aws_s3_bucket.hydrovis-nwm-incoming[0].id

  rule {
    id     = "30 Day Expiration"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 0
    }

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }
}

resource "aws_s3_bucket_replication_configuration" "hydrovis-nwm-incoming" {
  count  = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  bucket = aws_s3_bucket.hydrovis-nwm-incoming[0].id
  role   = aws_iam_role.nwm-replication[0].arn

  rule {
    id       = "HMLReplicationRoleToProdHML"
    priority = 0
    status   = "Enabled"
    filter {}

    destination {
      bucket = "arn:aws:s3:::hydrovis-prod-nwm-us-east-1"

      encryption_configuration {
        replica_kms_key_id = "arn:aws:kms:us-east-1:${var.prod_account_id}:alias/hydrovis-prod-nwm-us-east-1-s3"
      }
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
  }

  rule {
    id       = "HMLReplicationRoleToUatHML"
    priority = 1
    status   = "Enabled"
    filter {}

    destination {
      account = "${var.uat_account_id}"
      bucket     = "arn:aws:s3:::hydrovis-uat-nwm-us-east-1"

      encryption_configuration {
        replica_kms_key_id = "arn:aws:kms:us-east-1:${var.uat_account_id}:alias/hydrovis-uat-nwm-us-east-1-s3"
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

  rule {
    id       = "HMLReplicationRoleToTiHML"
    priority = 2
    status   = "Enabled"
    filter {}

    destination {
      account = "${var.ti_account_id}"
      bucket     = "arn:aws:s3:::hydrovis-ti-nwm-us-east-1"

      encryption_configuration {
        replica_kms_key_id = "arn:aws:kms:us-east-1:${var.ti_account_id}:alias/hydrovis-ti-nwm-us-east-1-s3"
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

resource "aws_s3_bucket_server_side_encryption_configuration" "hydrovis-nwm-incoming" {
  count  = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  bucket = aws_s3_bucket.hydrovis-nwm-incoming[0].bucket

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.hydrovis-nwm-incoming-s3[0].arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_versioning" "hydrovis-nwm-incoming" {
  count  = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  bucket = aws_s3_bucket.hydrovis-nwm-incoming[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "hydrovis-nwm-incoming" {
  count  = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  bucket = aws_s3_bucket.hydrovis-nwm-incoming[0].bucket

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
          Resource  = "${aws_s3_bucket.hydrovis-nwm-incoming[0].arn}/*"
          Sid       = "DenyUnEncryptedObjectUploads"
        },
      ]
    }
  )
}































resource "aws_kms_key" "hydrovis-pcpanl-incoming-s3" {
  count               = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  description         = "Symmetric CMK for KMS-KEY-ARN for pcpanl Incoming Bucket"
  enable_key_rotation = true
  policy = jsonencode(
    {
      Version = "2012-10-17"
      Id      = "key-hydrovis-prod-pcpanl-incoming-kms-cmk-policy"
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
              "arn:aws:iam::${var.prod_account_id}:user/hydrovis-data-prod-ingest-service-user",
              "arn:aws:iam::${var.prod_account_id}:role/hydrovis-prod-pcpanl-incoming-replication",
            ])
          }
          Resource = "*"
          Sid      = "Allow use of the key"
        },
      ]
    }
  )
}

resource "aws_kms_alias" "hydrovis-pcpanl-incoming-s3" {
  count = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  name          = "alias/noaa-nws-hydrovis-prod-pcpanl-incoming-s3-cmk-alias"
  target_key_id = aws_kms_key.hydrovis-pcpanl-incoming-s3[0].key_id
}

resource "aws_iam_role" "pcpanl-replication" {
  count = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  name  = "hydrovis-prod-pcpanl-incoming-replication"
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
    name   = "pcpanlBucketReplicationPolicy"
    policy = jsonencode(
      {
        Version = "2012-10-17"
        Statement = [
          {
            Action   = "iam:PassRole"
            Effect   = "Allow"
            Resource = "arn:aws:iam::${var.prod_account_id}:role/hydrovis-prod-pcpanl-incoming-replication"
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
              "arn:aws:s3:::hydrovis-prod-pcpanl-incoming-us-east-1/*",
              "arn:aws:s3:::hydrovis-prod-pcpanl-incoming-us-east-1",
            ]
            Sid = "VisualEditor8"
          },
          {
            Action = "kms:Decrypt"
            Condition = {
              StringLike = {
                "kms:ViaService" = "s3.us-east-1.amazonaws.com"
              }
            }
            Effect   = "Allow"
            Resource = aws_kms_key.hydrovis-pcpanl-incoming-s3[0].arn
            Sid      = "VisualEditor0"
          },
          {
            Action = "kms:Encrypt"
            Condition = {
              "ForAnyValue:StringLike" = {
                "kms:ResourceAliases" = "alias/hydrovis-*-pcpanl-*"
              }
              StringLike = {
                "kms:ViaService" = "s3.us-east-1.amazonaws.com"
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
              "arn:aws:s3:::hydrovis-*-pcpanl-*",
              "arn:aws:s3:::hydrovis-*-pcpanl-*/*",
            ]
            Sid = "VisualEditor5"
          },
        ]
      }
    )
  }
}

resource "aws_s3_bucket" "hydrovis-pcpanl-incoming" {
  count  = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  bucket = "hydrovis-prod-pcpanl-incoming-us-east-1"
}

resource "aws_s3_bucket_lifecycle_configuration" "hydrovis-pcpanl-incoming" {
  count  = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  bucket = aws_s3_bucket.hydrovis-pcpanl-incoming[0].id

  rule {
    id     = "30 Day Expiration"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 0
    }

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }
}

resource "aws_s3_bucket_replication_configuration" "hydrovis-pcpanl-incoming" {
  count  = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  bucket = aws_s3_bucket.hydrovis-pcpanl-incoming[0].id
  role   = aws_iam_role.pcpanl-replication[0].arn

  rule {
    id       = "pcpanlReplicationRoleToProdPcpanl"
    priority = 0
    status   = "Enabled"
    filter {}

    destination {
      bucket = "arn:aws:s3:::hydrovis-prod-pcpanl-us-east-1"

      encryption_configuration {
        replica_kms_key_id = "arn:aws:kms:us-east-1:${var.prod_account_id}:alias/hydrovis-prod-pcpanl-us-east-1-s3"
      }
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
  }

  rule {
    id       = "pcpanlReplicationRoleToUATPcpanl"
    priority = 1
    status   = "Enabled"
    filter {}

    destination {
      account = "${var.uat_account_id}"
      bucket     = "arn:aws:s3:::hydrovis-uat-pcpanl-us-east-1"

      encryption_configuration {
        replica_kms_key_id = "arn:aws:kms:us-east-1:${var.uat_account_id}:alias/hydrovis-uat-pcpanl-us-east-1-s3"
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

  rule {
    id       = "pcpanlReplicationRoleToTiPcpanl"
    priority = 2
    status   = "Enabled"
    filter {}

    destination {
      account = "${var.ti_account_id}"
      bucket     = "arn:aws:s3:::hydrovis-ti-pcpanl-us-east-1"

      encryption_configuration {
        replica_kms_key_id = "arn:aws:kms:us-east-1:${var.ti_account_id}:alias/hydrovis-ti-pcpanl-us-east-1-s3"
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

resource "aws_s3_bucket_server_side_encryption_configuration" "hydrovis-pcpanl-incoming" {
  count  = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  bucket = aws_s3_bucket.hydrovis-pcpanl-incoming[0].bucket

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.hydrovis-pcpanl-incoming-s3[0].arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_versioning" "hydrovis-pcpanl-incoming" {
  count  = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  bucket = aws_s3_bucket.hydrovis-pcpanl-incoming[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "hydrovis-pcpanl-incoming" {
  count  = var.environment == "prod" ? 1 : 0 // This makes sure this is only built when deploying to prod
  bucket = aws_s3_bucket.hydrovis-pcpanl-incoming[0].bucket

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
          Resource  = "${aws_s3_bucket.hydrovis-pcpanl-incoming[0].arn}/*"
          Sid       = "DenyUnEncryptedObjectUploads"
        },
      ]
    }
  )
}