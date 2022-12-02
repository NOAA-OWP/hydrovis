variable "environment" {
  type = string
}

variable "ami_owner_account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "instance_availability_zone" {
  type = string
}

variable "instance_profile_name" {
  type = string
}

variable "instance_subnet_id" {
  type = string
}

variable "instance_sgs" {
  type = list(string)
}

variable "deployment_bucket" {
  type = string
}

variable "saved_objects_s3_key" {
  type = string
}

variable "opensearch_domain_endpoint" {
  type = string
}

variable "dashboard_users_credentials_secret_strings" {
  type = list(string)
}

variable "dashboard_users_and_roles" {
  type = map(list(string))
}

variable "master_user_credentials_secret_string" {
  type = string
}


locals {
  cloudinit_config_data = {
    write_files = [
      for parser_template in fileset("${path.module}/parser_templates", "*.conf") :
      {
        path        = "/parsers/${parser_template}"
        permissions = "0777"
        owner       = "ec2-user:ec2-user"
        content     = templatefile("${path.module}/parser_templates/${parser_template}", {
          os_endpoint    = var.opensearch_domain_endpoint
          region         = var.region
          admin_username = jsondecode(var.master_user_credentials_secret_string)["username"]
          admin_password = jsondecode(var.master_user_credentials_secret_string)["password"]
        })
      }
    ]
  }

  dashboard_users_and_roles_creation_api_calls = <<EOT
# Add Global tenent to readall role
curl -XPATCH -u ${jsondecode(var.master_user_credentials_secret_string)["username"]}:${jsondecode(var.master_user_credentials_secret_string)["password"]} \
  https://${var.opensearch_domain_endpoint}/_plugins/_security/api/roles/readall \
  -H "Content-Type: application/json" \
  -H "osd-xsrf: true" \
  -d '[ { "op": "add", "path": "/tenant_permissions", "value": [ { "tenant_patterns": ["global_tenant"], "allowed_actions": ["kibana_all_read"] } ] } ]'

%{ for s in var.dashboard_users_credentials_secret_strings }
# Add user
curl -XPUT -u ${jsondecode(var.master_user_credentials_secret_string)["username"]}:${jsondecode(var.master_user_credentials_secret_string)["password"]} \
  https://${var.opensearch_domain_endpoint}/_plugins/_security/api/internalusers/${jsondecode(s)["username"]} \
  -H "Content-Type: application/json" \
  -H "osd-xsrf: true" \
  -d '{ "password": "${jsondecode(s)["password"]}" }'

%{ for r in var.dashboard_users_and_roles[jsondecode(s)["username"]] }
# Add user to specified role
curl -XPATCH -u ${jsondecode(var.master_user_credentials_secret_string)["username"]}:${jsondecode(var.master_user_credentials_secret_string)["password"]} \
  https://${var.opensearch_domain_endpoint}/_plugins/_security/api/rolesmapping \
  -H "Content-Type: application/json" \
  -H "osd-xsrf: true" \
  -d '[ { "op": "add", "path": "/${r}", "value": { "users": ["${jsondecode(s)["username"]}"] } } ]'
%{ endfor }
%{ endfor }
EOT
}

data "cloudinit_config" "startup" {
  part {
    content_type = "text/cloud-config"
    filename     = "cloud-config.yaml"
    content = <<-END
      #cloud-config
      ${jsonencode(local.cloudinit_config_data)}
    END
  }

  part {
    content_type = "text/x-shellscript"
    filename     = "startup.sh"
    content      = templatefile("${path.module}/startup.sh.tftpl", {
      os_endpoint                                  = var.opensearch_domain_endpoint
      admin_username                               = jsondecode(var.master_user_credentials_secret_string)["username"]
      admin_password                               = jsondecode(var.master_user_credentials_secret_string)["password"]
      deployment_bucket                            = var.deployment_bucket
      saved_objects_s3_key                         = var.saved_objects_s3_key
      dashboard_users_and_roles_creation_api_calls = local.dashboard_users_and_roles_creation_api_calls
    })
  }
}

resource "aws_instance" "logstash" {
  ami                    = data.aws_ami.linux.id
  iam_instance_profile   = var.instance_profile_name
  instance_type          = "t3.medium"
  availability_zone      = var.instance_availability_zone
  vpc_security_group_ids = var.instance_sgs
  subnet_id              = var.instance_subnet_id
  ebs_optimized          = true

  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    "Name" = "hv-${var.environment}-logstash-os"
    "OS"   = "Linux"
  }

  user_data = data.cloudinit_config.startup.rendered
  user_data_replace_on_change = true
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