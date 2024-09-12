variable "environment" {
  type = string
}

variable "mq_ingest_subnets" {
  type = list(any)
}

variable "mq_ingest_secret_string" {
  type = string
}

variable "mq_ingest_security_groups" {
  type = list(any)
}

resource "aws_mq_broker" "ingest" {
  # Don't ask
  broker_name                = "hv-vpp-${var.environment}-dataingest-rabbitmq-${substr(md5(jsondecode(var.mq_ingest_secret_string)["password"]), 0, 6)}"
  auto_minor_version_upgrade = false
  apply_immediately          = true
  engine_type                = "RabbitMQ"
  engine_version             = "3.8.27"
  host_instance_type         = "mq.t3.micro"
  publicly_accessible        = false
  security_groups            = var.mq_ingest_security_groups
  subnet_ids                 = var.mq_ingest_subnets

  lifecycle {
    ignore_changes = [engine_version]
  }

  logs {
    general = true
  }

  user {
    username = jsondecode(var.mq_ingest_secret_string)["username"]
    password = jsondecode(var.mq_ingest_secret_string)["password"]
  }
}

output "mq-ingest" {
  value     = aws_mq_broker.ingest
  sensitive = true
}
