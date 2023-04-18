variable "environment" {
  type = string
}

variable "account_id" {
  type = string
}

variable "active_region" {
  type = string
}

variable "egis_health_checks" {
  type = map(map(string))
}


locals {
  zone_names = {
    uat = "maps-staging.water.noaa.gov"
    prod = "maps.water.noaa.gov"
  }
}


# Base DNS Zone
resource "aws_route53_zone" "public" {
  name = local.zone_names[var.environment]

  tags = {
    Name = local.zone_names[var.environment]
  }
}


# DNSSEC
resource "aws_kms_key" "public" {
  customer_master_key_spec = "ECC_NIST_P256"
  deletion_window_in_days  = 7
  key_usage                = "SIGN_VERIFY"
  policy = jsonencode({
    "Version": "2012-10-17",
    "Id": "dnssec-policy",
    "Statement": [
      {
        "Sid": "Enable IAM User Permissions",
        "Effect": "Allow",
        "Principal": {
          "AWS": "arn:aws:iam::${var.account_id}:root"
        },
        "Action": "kms:*",
        "Resource": "*"
      },
      {
        "Sid": "Allow Route 53 DNSSEC Service",
        "Effect": "Allow",
        "Principal": {
          "Service": "dnssec-route53.amazonaws.com"
        },
        "Action": [
          "kms:DescribeKey",
          "kms:GetPublicKey",
          "kms:Sign"
        ],
        "Resource": "*",
        "Condition": {
          "StringEquals": {
            "aws:SourceAccount": var.account_id
          },
          "ArnLike": {
            "aws:SourceArn": "arn:aws:route53:::hostedzone/*"
          }
        }
      },
      {
        "Sid": "Allow Route 53 DNSSEC to CreateGrant",
        "Effect": "Allow",
        "Principal": {
          "Service": "dnssec-route53.amazonaws.com"
        },
        "Action": "kms:CreateGrant",
        "Resource": "*",
        "Condition": {
          "Bool": {
            "kms:GrantIsForAWSResource": "true"
          }
        }
      }
    ]
  })
}
resource "aws_kms_alias" "public" {
  name          = "alias/noaaroute53"
  target_key_id = aws_kms_key.public.key_id
}
resource "aws_route53_key_signing_key" "public" {
  hosted_zone_id             = aws_route53_zone.public.id
  key_management_service_arn = aws_kms_key.public.arn
  name                       = "NOAARoute53"
}
resource "aws_route53_hosted_zone_dnssec" "public" {
  depends_on = [
    aws_route53_key_signing_key.public
  ]
  hosted_zone_id = aws_route53_key_signing_key.public.hosted_zone_id
}


# Health Check and Failover DNS Records
# resource "aws_route53_health_check" "egis_health_check" {
#   for_each = var.egis_health_checks

#   type                            = "CLOUDWATCH_METRIC"
#   cloudwatch_alarm_name           = each.value["alarm_name"]
#   cloudwatch_alarm_region         = each.key
#   insufficient_data_health_status = "LastKnownStatus"

#   tags = {
#     Name = "egis-health-check-${each.key}"
#   }
# }
resource "aws_route53_record" "egis_alb" {
  for_each = var.egis_health_checks

  zone_id = aws_route53_zone.public.id
  name    = aws_route53_zone.public.name
  type    = "A"

  alias {
    evaluate_target_health = false
    # evaluate_target_health = true
    name                   = "dualstack.${each.value["alb_host"]}"
    zone_id                = each.value["alb_zone_id"]
  }

  weighted_routing_policy {
    weight = var.active_region == each.key ? 255 : 0
  }

  set_identifier = each.key
  # health_check_id = aws_route53_health_check.egis_health_check[each.key].id
}