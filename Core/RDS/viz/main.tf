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
    name         = "rds.custom_dns_resolution"
    value        = "1"
    apply_method = "pending-reboot"
  }
  



  parameter {
    name  = "autovacuum"
    value = "1"
  }

  parameter {
    name  = "autovacuum_analyze_scale_factor"
    value = "0.005"
  }

  parameter {
    name  = "autovacuum_max_workers"
    value = "4"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "autovacuum_vacuum_scale_factor"
    value = "0.05"
  }

  parameter {
    name  = "autovacuum_work_mem"
    value = "2128000"
  }

  parameter {
    name  = "checkpoint_completion_target"
    value = "0.9"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "default_statistics_target"
    value = "100"
  }

  parameter {
    name  = "effective_cache_size"
    value = "8576"
  }

  parameter {
    name  = "effective_io_concurrency"
    value = "200"
  }

  parameter {
    name  = "geqo_threshold"
    value = "12"
  }

  parameter {
    name  = "huge_pages"
    value = "off"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "idle_in_transaction_session_timeout"
    value = "900000"
  }

  parameter {
    name  = "log_autovacuum_min_duration"
    value = "100"
  }

  parameter {
    name  = "max_connections"
    value = "200"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "maintenance_work_mem"
    value = "2526332"
  }

  parameter {
    name  = "max_worker_processes"
    value = "8"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "max_parallel_workers_per_gather"
    value = "4"
  }

  parameter {
    name  = "max_parallel_workers"
    value = "8"
  }

  parameter {
    name  = "max_parallel_maintenance_workers"
    value = "4"
  }

  parameter {
    name  = "max_replication_slots"
    value = "10"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "max_wal_senders"
    value = "10"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "max_wal_size"
    value = "6384"
  }

  parameter {
    name  = "min_wal_size"
    value = "2096"
  }

  parameter {
    name  = "random_page_cost"
    value = "1.1"
  }

  parameter {
    name  = "shared_buffers"
    value = "6291456"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "track_wal_io_timing"
    value = "0"
  }

  parameter {
    name  = "wal_buffers"
    value = "262143"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "wal_writer_flush_after"
    value = "128000"
  }

  parameter {
    name  = "work_mem"
    value = "2680000"
  }
}

resource "aws_db_instance" "hydrovis" {
  identifier                   = "hv-vpp-${var.environment}-viz-processing"
  db_name                      = var.viz_db_name
  instance_class               = "db.m6g.2xlarge"
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