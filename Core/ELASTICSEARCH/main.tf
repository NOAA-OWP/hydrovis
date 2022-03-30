variable "environment" {
  type = string
}

variable "ami_owner_account_id" {
  type        = string
}

variable "region" {
  type = string
}

variable "availability_zone" {
  type = string
}

variable "es_sgs" {
  type = list(string)
}

variable "ec2_instance_sgs" {
  type = list(string)
}

variable "data_subnets" {
  type = list(string)
}

variable "ec2_instance_profile_name" {
  type = string
}

variable "ec2_instance_subnet" {
  type = string
}

variable "deployment_bucket" {
  type = string
}

resource "aws_iam_service_linked_role" "es" {
  aws_service_name = "es.amazonaws.com"
}

resource "aws_cloudwatch_log_group" "es_loggroup" {
  name = "/aws/OpenSearchService/domains/monitoring-hydrovis/application-logs"
}

resource "aws_cloudwatch_log_resource_policy" "es_loggroup" {
  policy_name = "es_loggroup"

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

resource "aws_elasticsearch_domain" "es" {
  domain_name           = "monitoring-hydrovis"
  elasticsearch_version = "7.10"

  cluster_config {
    instance_count         = 2
    instance_type          = "r5.large.elasticsearch"
    zone_awareness_enabled = true

    zone_awareness_config {
      availability_zone_count = 2
    }
  }

  vpc_options {
    subnet_ids         = var.data_subnets
    security_group_ids = var.es_sgs
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 100
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.es_loggroup.arn
    log_type                 = "ES_APPLICATION_LOGS"
  }

  access_policies = <<CONFIG
  {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "es:*",
            "Principal": "*",
            "Effect": "Allow",
            "Resource": "arn:aws:es:${var.region}:${var.account_id}:domain/monitoring-hydrovis/*"
        }
    ]
  }
  CONFIG

  snapshot_options {
    automated_snapshot_start_hour = 23
  }

  depends_on = [
    aws_iam_service_linked_role.es
  ]

  tags = {
    Domain = "monitoring-hydrovis"
    name   = "monitoring-hydrovis"
  }
}

data "template_file" "parser_templates" {
  for_each = fileset("${path.module}/parsers", "*.conf.template")
  template = file("${path.module}/parsers/${each.value}")
  vars = {
    parser_name = regex("(.+).template", each.value)[0] # Not used in the template, just in the for loop below
    es_endpoint = aws_elasticsearch_domain.es.endpoint
    region      = var.region
  }
}

data "template_file" "startup" {
  template = file("${path.module}/startup.sh")
  vars = {
    es_endpoint       = aws_elasticsearch_domain.es.endpoint
    deployment_bucket = var.deployment_bucket
  }
}

data "cloudinit_config" "startup" {
  # gzip          = false
  # base64_encode = false

  part {
    content_type = "text/cloud-config"
    filename     = "cloud-config.yaml"
    content = <<-END
      #cloud-config
      ${jsonencode({ write_files = [for parser_template in data.template_file.parser_templates :
    {
      path        = "/parsers/${parser_template.vars["parser_name"]}"
      permissions = "0777"
      owner       = "ec2-user:ec2-user"
      content     = "${parser_template.rendered}"
    }
] })}
    END
}

part {
  content_type = "text/x-shellscript"
  filename     = "startup.sh"
  content      = data.template_file.startup.rendered
}
}

# data "cloudinit_config" "startup" {
#   # gzip          = false
#   # base64_encode = false

#   part {
#     content_type = "text/cloud-config"
#     filename     = "cloud-config.yaml"
#     content = <<-END
#       #cloud-config
#       ${jsonencode({ write_files = [for parser in fileset(path.module, "parsers/*.conf") :
#         {
#           path        = "/${parser}"
#           permissions = "0777"
#           owner       = "ec2-user:ec2-user"
#           content     = "${file("${path.module}/${parser}")}"
#         }
#       ]})}
#     END
#   }

#   part {
#     content_type = "text/x-shellscript"
#     filename     = "startup.sh"
#     content      = file("${path.module}/startup.sh")
#   }
# }

resource "aws_instance" "logstash" {
  ami                    = data.aws_ami.linux.id
  iam_instance_profile   = var.ec2_instance_profile_name
  instance_type          = "t3.medium"
  availability_zone      = var.availability_zone
  vpc_security_group_ids = var.ec2_instance_sgs
  subnet_id              = var.ec2_instance_subnet
  ebs_optimized          = true

  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    "Name" = "hv-${var.environment}-logstash"
    "OS"   = "Linux"
  }

  user_data = data.cloudinit_config.startup.rendered
}

data "aws_ami" "linux" {
  most_recent = true
  filter {
    name   = "name"
    values = ["hydrovis-amznlinux2-STIGD*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = [var.ami_owner_account_id]
}

output "aws_instance_logstash" {
  value = aws_instance.logstash
}

output "aws_elasticsearch_domain" {
  value = aws_elasticsearch_domain.es
}