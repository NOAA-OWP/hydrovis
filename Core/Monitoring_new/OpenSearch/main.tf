variable "environment" {
  type = string
}

variable "account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "opensearch_security_group_ids" {
  type = list(string)
}

variable "data_subnet_ids" {
  type = list(string)
}

variable "master_user_credentials_secret_string" {
  type = string
}

variable "deployment_bucket" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "task_role_arn" {
  type = string
}

variable "execution_role_arn" {
  type = string
}

# Creates an nginx proxy to forward traffic from the public load balancer to the OpenSearch Domain
module "nginx-proxy" {
  source = "./NginxProxy"

  environment = var.environment
  region      = var.region

  domain_endpoint               = aws_opensearch_domain.hydrovis.endpoint
  deployment_bucket             = var.deployment_bucket
  data_subnet_ids               = var.data_subnet_ids
  opensearch_security_group_ids = var.opensearch_security_group_ids
  vpc_id                        = var.vpc_id
  task_role_arn                 = var.task_role_arn
  execution_role_arn            = var.execution_role_arn
}


resource "aws_iam_service_linked_role" "os" {
  aws_service_name = "opensearchservice.amazonaws.com"
}

resource "aws_cloudwatch_log_group" "os_loggroup" {
  name = "/aws/OpenSearchService/domains/monitoring-hydrovis-os/application-logs"
}

resource "aws_cloudwatch_log_resource_policy" "os_loggroup" {
  policy_name = "os_loggroup"

  policy_document = <<CONFIG
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "es.amazonaws.com"
      },
      "Action": [
        "logs:PutLogEvents",
        "logs:PutLogEventsBatch",
        "logs:CreateLogStream"
      ],
      "Resource": "arn:aws:logs:*"
    }
  ]
}
CONFIG
}

resource "aws_s3_object" "saved_objects" {
  bucket      = var.deployment_bucket
  key         = "monitoring/saved_objects.ndjson"
  source      = "${path.module}/saved_objects.ndjson"
  source_hash = filemd5("${path.module}/saved_objects.ndjson")
}

resource "aws_opensearch_domain" "hydrovis" {
  domain_name      = "monitoring-hydrovis-os"
  engine_version   = "OpenSearch_2.3"  

  cluster_config {
    dedicated_master_count   = 3
    dedicated_master_enabled = true
    dedicated_master_type    = "r5.large.search"
    instance_count           = 2
    instance_type            = "r5.large.search"
    zone_awareness_enabled   = true
  }

  access_policies  = jsonencode(
    {
      Statement = [
        {
          Action    = "es:*"
          Effect    = "Allow"
          Principal = "*"
          Resource  = "arn:aws:es:${var.region}:${var.account_id}:domain/monitoring-hydrovis-os/*"
        },
      ]
      Version = "2012-10-17"
    }
  )

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.os_loggroup.arn
    log_type                 = "ES_APPLICATION_LOGS"
  }

  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = true

    master_user_options {
      master_user_name     = jsondecode(var.master_user_credentials_secret_string)["username"]
      master_user_password = jsondecode(var.master_user_credentials_secret_string)["password"]
    }
  }

  auto_tune_options {
    desired_state       = "ENABLED"
    rollback_on_disable = "NO_ROLLBACK"
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 100
    iops        = 3000
  }

  encrypt_at_rest {
    enabled = true
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  snapshot_options {
    automated_snapshot_start_hour = 0
  }

  vpc_options {
    subnet_ids         = var.data_subnet_ids
    security_group_ids = var.opensearch_security_group_ids
  }

  depends_on = [aws_iam_service_linked_role.os]

  tags = {
    Domain = "monitoring-hydrovis-os"
  }
}

output "domain_endpoint" {
  value = aws_opensearch_domain.hydrovis.endpoint
}

output "domain_arn" {
  value = aws_opensearch_domain.hydrovis.arn
}

output "saved_objects_s3_key" {
  value = aws_s3_object.saved_objects.key
}