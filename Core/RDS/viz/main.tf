variable "environment" {
  type = string
}

variable "db_viz_processing_security_groups" {
  type = list(any)
}

variable "rds_kms_key" {
  type = string
}

variable "subnet-a" {
  type = string
}

variable "subnet-b" {
  type = string
}

variable "db_viz_processing_secret_string" {
  type = string
}

variable "viz_db_name" {
  type = string
}

variable "role_rds_s3_export_arn" {
  type = string
}

variable "private_route_53_zone" {
  type = object({
    name     = string
    zone_id  = string
  })
}


resource "aws_db_subnet_group" "hydrovis" {
  name       = "hv-vpp-${var.environment}-viz-processing"
  subnet_ids = [var.subnet-a, var.subnet-b]
  tags = {
    Name = "Viz Processing Subnet Group"
  }
}

resource "aws_db_parameter_group" "hydrovis" {
  name   = "hv-vpp-${var.environment}-viz-processing"
  family = "postgres15"

  parameter {
    name  = "checkpoint_timeout"
    value = "1800"
  }

  parameter {
    name  = "max_wal_size"
    value = var.environment == "ti" ? "4048" : "8048"
  }

  parameter {
    name  = "min_wal_size"
    value = "2048"
  }

  parameter {
    name  = "maintenance_work_mem"
    value = "1026332"
  }

  parameter {
    name  = "max_worker_processes"
    value = "8"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "rds.custom_dns_resolution"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "wal_buffers"
    value = var.environment == "ti" ? "64000" : "128000"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "work_mem"
    value = var.environment == "ti" ? "262144" : "1048576"
  }
}

resource "aws_db_instance" "hydrovis" {
  identifier                   = "hv-vpp-${var.environment}-viz-processing"
  db_name                      = var.viz_db_name
  instance_class               = var.environment == "ti" ? "db.m6g.2xlarge" : "db.m5.4xlarge"
  allocated_storage            = 1024
  storage_type                 = "gp2"
  engine                       = "postgres"
  engine_version               = "15.3"
  username                     = jsondecode(var.db_viz_processing_secret_string)["username"]
  password                     = jsondecode(var.db_viz_processing_secret_string)["password"]
  db_subnet_group_name         = aws_db_subnet_group.hydrovis.name
  vpc_security_group_ids       = var.db_viz_processing_security_groups
  kms_key_id                   = var.rds_kms_key
  parameter_group_name         = aws_db_parameter_group.hydrovis.name
  storage_encrypted            = true
  copy_tags_to_snapshot        = true
  performance_insights_enabled = true
  backup_retention_period      = 7
  skip_final_snapshot          = true
  auto_minor_version_upgrade   = false
  tags = {
    "hv-vpp-${var.environment}-viz-processing-rdsdbtag" : "hv-vpp-${var.environment}-viz-processing-rdsdbtag"
    "noaa:monitoring"                                   : "true"
  }
}

resource "aws_db_instance_role_association" "hydrovis" {
  db_instance_identifier = aws_db_instance.hydrovis.id
  feature_name           = "s3Export"
  role_arn               = var.role_rds_s3_export_arn
}

resource "aws_route53_record" "hydrovis" {
  zone_id = var.private_route_53_zone.zone_id
  name    = "rds-viz.${var.private_route_53_zone.name}"
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