variable "environment" {
  type = string
}

variable "subnet-data1a" {
  type = string
}
variable "subnet-data1b" {
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

resource "aws_db_subnet_group" "ingest" {
  name       = "rds_ingest_${var.environment}"
  subnet_ids = [var.subnet-data1a, var.subnet-data1b]

  tags = {
    Name = "My DB subnet group"
  }
}

resource "aws_db_instance" "ingest" {
  identifier                   = "hydrovis-${var.environment}-ingest"
  name                         = "rfcfcst"
  instance_class               = "db.r6g.large"
  allocated_storage            = 100
  storage_type                 = "gp2"
  engine                       = "postgres"
  engine_version               = "12.7"
  username                     = jsondecode(var.db_ingest_secret_string)["username"]
  password                     = jsondecode(var.db_ingest_secret_string)["password"]
  db_subnet_group_name         = aws_db_subnet_group.ingest.name
  vpc_security_group_ids       = var.db_ingest_security_groups
  kms_key_id                   = var.rds_kms_key
  storage_encrypted            = true
  copy_tags_to_snapshot        = true
  performance_insights_enabled = true
  backup_retention_period      = 7
  skip_final_snapshot          = true
  tags = {
    "hydrovis-${var.environment}-data-ingest-rdsdbtag" : "hydrovis-${var.environment}-data-ingest-rdsdbtag"
  }
}

output "rds-ingest" {
  value = aws_db_instance.ingest
}

output "rds-ingest-connection-string" {
  value = "jdbc:postgresql://${aws_db_instance.ingest.address}:${aws_db_instance.ingest.port}/${aws_db_instance.ingest.name}"
}
