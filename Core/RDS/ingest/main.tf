variable "environment" {
  type = string
}

variable "subnet-a" {
  type = string
}
variable "subnet-b" {
  type = string
}

variable "db_ingest_secret_string" {
  type = string
}

variable "db_ingest_security_groups" {
  type = list(any)
}

variable "rds_kms_key" {
  type = string
}

variable "private_route_53_zone" {
  type = object({
    name     = string
    zone_id  = string
  })
}


resource "aws_db_subnet_group" "hydrovis" {
  name       = "hv-vpp-${var.environment}-ingest"
  subnet_ids = [var.subnet-a, var.subnet-b]

  tags = {
    Name = "Data Ingest Subnet Group"
  }
}

resource "aws_db_instance" "hydrovis" {
  identifier                   = "hv-vpp-${var.environment}-ingest"
  db_name                      = "rfcfcst"
  instance_class               = "db.r6g.large"
  allocated_storage            = 500
  storage_type                 = "gp2"
  engine                       = "postgres"
  engine_version               = "12.8"
  username                     = jsondecode(var.db_ingest_secret_string)["username"]
  password                     = jsondecode(var.db_ingest_secret_string)["password"]
  db_subnet_group_name         = aws_db_subnet_group.hydrovis.name
  vpc_security_group_ids       = var.db_ingest_security_groups
  kms_key_id                   = var.rds_kms_key
  storage_encrypted            = true
  copy_tags_to_snapshot        = true
  performance_insights_enabled = true
  backup_retention_period      = 7
  skip_final_snapshot          = true
  auto_minor_version_upgrade   = false
  tags = {
    "hv-vpp-${var.environment}-data-ingest-rdsdbtag" : "hv-vpp-${var.environment}-data-ingest-rdsdbtag"
    "noaa:monitoring"                                : "true"
  }
}

resource "aws_route53_record" "hydrovis" {
  zone_id = var.private_route_53_zone.zone_id
  name    = "rds-ingest.${var.private_route_53_zone.name}"
  type    = "CNAME"
  ttl     = 300
  records = [aws_db_instance.hydrovis.address]
}


output "instance" {
  value = aws_db_instance.hydrovis
}

output "dns_name" {
  value = aws_route53_record.hydrovis.name
}