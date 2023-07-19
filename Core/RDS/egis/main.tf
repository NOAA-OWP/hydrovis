variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "private_route_53_zone" {
  type = object({
    name     = string
    zone_id  = string
  })
}

locals {
  db_instance_names = {
    us-east-1 = {
      ti = "hv-ti-egis-rds-pg-egdb"
    }
    us-east-2 = {
    }
  }
}

# Import EGIS DB
data "aws_db_instance" "hydrovis" {
  db_instance_identifier = local.db_instance_names[var.region][var.environment]
}

resource "aws_route53_record" "hydrovis" {
  zone_id = var.private_route_53_zone.zone_id
  name    = "rds-egis.${var.private_route_53_zone.name}"
  type    = "CNAME"
  ttl     = 300
  records = [data.aws_db_instance.hydrovis.address]
}


output "instance" {
  value = data.aws_db_instance.hydrovis
}

output "dns_name" {
  value = aws_route53_record.hydrovis.name
}