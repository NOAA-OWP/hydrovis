variable "account_id" {
  type = string
}

variable "dns_records" {
  type = any
}


# Base DNS Zone
resource "aws_route53_zone" "public" {
  name = var.dns_records["domain"]

  tags = {
    Name = var.dns_records["domain"]
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
  name                       = "WaterNOAAGovRoute53"
}

resource "aws_route53_hosted_zone_dnssec" "public" {
  depends_on = [
    aws_route53_key_signing_key.public
  ]
  hosted_zone_id = aws_route53_key_signing_key.public.hosted_zone_id
}


module "weighted-aliases" {
  source   = "./WeightedAlias"
  for_each = var.dns_records["weighted_alias"]

  aliases = each.value
  zone    = aws_route53_zone.public
}

resource "aws_route53_record" "aliases" {
  for_each = var.dns_records["alias"]

  zone_id = aws_route53_zone.public.id
  name    = each.key
  type    = "A"

  alias {
    evaluate_target_health = false
    name                   = each.value["alb_host"]
    zone_id                = each.value["alb_zone_id"]
  }
}

resource "aws_route53_record" "as" {
  for_each = var.dns_records["a"]

  zone_id = aws_route53_zone.public.id
  name    = each.key
  type    = "A"
  ttl     = 300
  records = [each.value]
}

resource "aws_route53_record" "cnames" {
  for_each = var.dns_records["cname"]

  zone_id = aws_route53_zone.public.id
  name    = each.key
  type    = "CNAME"
  ttl     = 300
  records = [each.value]
}