variable "environment" {
  type = string
}

variable "private_route_53_zone" {
  type = object({
    name     = string
    zone_id  = string
  })
}

# Import EGIS DB
data "aws_db_instance" "hydrovis" {
  db_instance_identifier = "hv-${var.environment == "prod" ? "prd" : var.environment}-egis-data-pg-egdb"
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