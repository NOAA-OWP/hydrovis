variable "name" {
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

variable "admin_team_arns" {
  type = list(string)
}

variable "access_principal_arns" {
  type = list(string)
}

resource "aws_kms_key" "hydrovis" {
  description         = "Used for ${var.name}"
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

resource "aws_kms_alias" "hydrovis" {
  name          = "alias/hydrovis-${var.environment}-${var.name}-${var.region}"
  target_key_id = aws_kms_key.hydrovis.key_id
}

output "arn" {
  value = aws_kms_key.hydrovis.arn
}