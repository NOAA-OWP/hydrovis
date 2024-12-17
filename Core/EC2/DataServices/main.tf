variable "environment" {
  type = string
}

variable "region" {
  type        = string
}

variable "account_id" {
  type        = string
}

variable "ec2_instance_subnet" {
  type = string
}

variable "ec2_instance_availability_zone" {
  type = string
}

variable "ec2_instance_sgs" {
  type = list(string)
}

variable "ec2_instance_profile_name" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "rds_host" {
  type = string
}

variable "location_db_name" {
  type = string
}

variable "forecast_db_name" {
  type = string
}

variable "location_credentials_secret_string" {
  type = string
}

variable "forecast_credentials_secret_string" {
  type = string
}

variable "vlab_repo_prefix" {
  type = string
}

variable "data_services_versions" {
  type = map(string)
}

variable "private_route_53_zone" {
  type = object({
    name     = string
    zone_id  = string
  })
}


# THIS TF CONFIG IS DEPENDANT ON A SSH KEY THAT CAN ACCESS THE WRDS VLAB REPOS
locals {
  ssh_key_filename          = "id_ed25519"
  cloudinit_config_data = {
    write_files = [
      {
        path        = "/home/ec2-user/.ssh/${local.ssh_key_filename}"
        permissions = "0400"
        owner       = "ec2-user:ec2-user"
        content     = file("${path.root}/sensitive/vpp/DataServices/${local.ssh_key_filename}")
      },
      {
        path        = "/wrds/apis.conf"
        permissions = "0777"
        owner       = "ec2-user:ec2-user"
        content     = file("${path.module}/data/nginx-apis.conf")
      },
      {
        path        = "/wrds/docker-compose-infrastructure.yml"
        permissions = "0777"
        owner       = "ec2-user:ec2-user"
        content     = file("${path.module}/data/docker-compose/docker-compose-infrastructure.yml")
      },
      {
        path        = "/wrds/location.env"
        permissions = "0777"
        owner       = "ec2-user:ec2-user"
        content     = templatefile("${path.module}/templates/env/location.env.tftpl", {
          db_name     = var.location_db_name
          db_username = jsondecode(var.location_credentials_secret_string)["username"]
          db_password = jsondecode(var.location_credentials_secret_string)["password"]
          db_host     = var.rds_host
          db_port     = "5432"
          environment = var.environment
        })
      },
      {
        path        = "/wrds/docker-compose-location.yml"
        permissions = "0777"
        owner       = "ec2-user:ec2-user"
        content     = file("${path.module}/data/docker-compose/docker-compose-location.yml")
      },
      {
        path        = "/wrds/requirements-location.txt"
        permissions = "0777"
        owner       = "ec2-user:ec2-user"
        content     = file("${path.module}/data/requirements/requirements-location.txt")
      },
      {
        path        = "/wrds/Dockerfile.location"
        permissions = "0777"
        owner       = "ec2-user:ec2-user"
        content     = file("${path.module}/data/Dockerfile/Dockerfile.location")
      },
      {
        path        = "/wrds/forecast.env"
        permissions = "0777"
        owner       = "ec2-user:ec2-user"
        content     = templatefile("${path.module}/templates/env/forecast.env.tftpl", {
          db_name          = var.forecast_db_name
          location_db_name = var.location_db_name
          db_username      = jsondecode(var.forecast_credentials_secret_string)["username"]
          db_password      = jsondecode(var.forecast_credentials_secret_string)["password"]
          db_host          = var.rds_host
          db_port          = "5432"
          environment      = var.environment
        })
      },
      {
        path        = "/wrds/docker-compose-forecast.yml"
        permissions = "0777"
        owner       = "ec2-user:ec2-user"
        content     = file("${path.module}/data/docker-compose/docker-compose-forecast.yml")
      },
      {
        path        = "/wrds/requirements-forecast.txt"
        permissions = "0777"
        owner       = "ec2-user:ec2-user"
        content     = file("${path.module}/data/requirements/requirements-forecast.txt")
      },
      {
        path        = "/wrds/Dockerfile.forecast"
        permissions = "0777"
        owner       = "ec2-user:ec2-user"
        content     = file("${path.module}/data/Dockerfile/Dockerfile.forecast")
      },
    ]
  }
}

# Writes the ssh key, .env files, and docker-compose.yml files to EC2 and starts the startup.sh
data "cloudinit_config" "startup" {
  gzip          = false
  base64_encode = false

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
    content      = templatefile("${path.module}/templates/startup.sh.tftpl", {
      vlab_repo_prefix         = var.vlab_repo_prefix
      infrastructure_commit    = var.data_services_versions["infrastructure_commit"]
      location_api_3_0_commit  = var.data_services_versions["location_api_3_0_commit"]
      forecast_api_2_0_commit  = var.data_services_versions["forecast_api_2_0_commit"]
      ssh_key_filename         = local.ssh_key_filename
      logging_application_name = "data_services"
    })
  }
}

# EC2 Related Resources
resource "aws_instance" "data_services" {
  ami                    = data.aws_ami.linux.id
  iam_instance_profile   = var.ec2_instance_profile_name
  instance_type          = "c5.xlarge"
  availability_zone      = var.ec2_instance_availability_zone
  vpc_security_group_ids = var.ec2_instance_sgs
  subnet_id              = var.ec2_instance_subnet
  key_name               = "hv-${var.environment}-ec2-key-pair-${var.region}"

  lifecycle {
    ignore_changes = [ami]
  }

  root_block_device {
    encrypted  = true
    kms_key_id = var.kms_key_arn
  }

  tags = {
    Name = "hv-vpp-${var.environment}-data-services"
    OS   = "Linux"
  }

  # This runs the cloud-init config, copying the SSH key to the EC2 and running the startup.sh script.
  user_data                   = data.cloudinit_config.startup.rendered
  user_data_replace_on_change = true
}

resource "aws_route53_record" "hydrovis" {
  zone_id = var.private_route_53_zone.zone_id
  name    = "data-services.${var.private_route_53_zone.name}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.data_services.private_ip]
}

data "aws_ami" "linux" {
  most_recent = true
  filter {
    name   = "name"
    values = ["amazon-linux-2-git-docker-psql-stig*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = [var.account_id]
}

output "dns_name" {
  value = aws_route53_record.hydrovis.name
}
