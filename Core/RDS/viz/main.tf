variable "environment" {
  type = string
}

variable "db_viz_processing_security_groups" {
  type = list(any)
}

variable "rds_kms_key" {
  type = string
}

variable "subnet-app1a" {
  type = string
}

variable "subnet-app1b" {
  type = string
}

variable "db_viz_processing_secret_string" {
  type = string
}

variable "viz_db_name" {
  type = string
}

resource "aws_db_subnet_group" "viz-processing" {
  name       = "rds_viz-processing_${var.environment}"
  subnet_ids = [var.subnet-app1a, var.subnet-app1b]
  tags = {
    Name = "Viz Processing Subnet Group"
  }
}

resource "aws_db_instance" "viz-processing" {
  identifier                   = "hydrovis-${var.environment}-viz-processing"
  db_name                      = var.viz_db_name
  instance_class               = "db.m6g.xlarge"
  allocated_storage            = 400
  storage_type                 = "gp2"
  engine                       = "postgres"
  engine_version               = "12.8"
  username                     = jsondecode(var.db_viz_processing_secret_string)["username"]
  password                     = jsondecode(var.db_viz_processing_secret_string)["password"]
  db_subnet_group_name         = aws_db_subnet_group.viz-processing.name
  vpc_security_group_ids       = var.db_viz_processing_security_groups
  kms_key_id                   = var.rds_kms_key
  storage_encrypted            = true
  copy_tags_to_snapshot        = true
  performance_insights_enabled = true
  backup_retention_period      = 7
  skip_final_snapshot          = true
  auto_minor_version_upgrade   = false
  tags = {
    "hydrovis-${var.environment}-viz-processing-rdsdbtag" : "hydrovis-${var.environment}-viz-processing-rdsdbtag"
  }
}

output "rds-viz-processing" {
  value = aws_db_instance.viz-processing
}