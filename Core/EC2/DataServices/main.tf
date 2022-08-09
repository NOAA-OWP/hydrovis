variable "environment" {
  type = string
}

variable "ami_owner_account_id" {
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

variable "logstash_ip" {
  type = string
}

variable "vlab_repo_prefix" {
  type = string
}

variable "data_services_versions" {
  type = map(string)
}

# THIS TF CONFIG IS DEPENDANT ON A SSH KEY THAT CAN ACCESS THE WRDS VLAB REPOS

locals {
  ssh_key_filename        = "id_ed25519"
  cloudinit_config_data = {
    write_files = [
      {
        path        = "/home/ec2-user/.ssh/${local.ssh_key_filename}"
        permissions = "0400"
        owner       = "ec2-user:ec2-user"
        content     = file("${path.root}/sensitive/DataServices/${local.ssh_key_filename}")
      },
      {
        path        = "/wrds/docker-compose-infrastructure.yml"
        permissions = "0777"
        owner       = "ec2-user:ec2-user"
        content     = templatefile("${path.module}/templates/docker-compose/docker-compose-infrastructure.yml.tftpl", {
          environment = var.environment
        })
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
        content     = templatefile("${path.module}/templates/docker-compose/docker-compose-location.yml.tftpl", {
          environment = var.environment
        })
      },
      {
        path        = "/wrds/forecast-2.0.env"
        permissions = "0777"
        owner       = "ec2-user:ec2-user"
        content     = templatefile("${path.module}/templates/env/forecast-2.0.env.tftpl", {
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
        path        = "/wrds/docker-compose-forecast-2.0.yml"
        permissions = "0777"
        owner       = "ec2-user:ec2-user"
        content     = templatefile("${path.module}/templates/docker-compose/docker-compose-forecast-2.0.yml.tftpl", {
          environment = var.environment
        })
      },
      {
        path        = "/wrds/forecast-1.1.env"
        permissions = "0777"
        owner       = "ec2-user:ec2-user"
        content     = templatefile("${path.module}/templates/env/forecast-1.1.env.tftpl", {
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
        path        = "/wrds/docker-compose-forecast-1.1.yml"
        permissions = "0777"
        owner       = "ec2-user:ec2-user"
        content     = templatefile("${path.module}/templates/docker-compose/docker-compose-forecast-1.1.yml.tftpl", {
          environment = var.environment
        })
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
    content      = templatefile("${path.module}/startup.sh.tftpl", {
      vlab_repo_prefix        = var.vlab_repo_prefix
      infrastructure_commit   = var.data_services_versions["infrastructure_commit"]
      location_api_3_0_commit = var.data_services_versions["location_api_3_0_commit"]
      forecast_api_2_0_commit = var.data_services_versions["forecast_api_2_0_commit"]
      forecast_api_1_1_commit = var.data_services_versions["forecast_api_1_1_commit"]
      ssh_key_filename        = local.ssh_key_filename
      logstash_ip             = var.logstash_ip
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

  lifecycle {
    ignore_changes = [ami]
  }

  root_block_device {
    encrypted  = true
    kms_key_id = var.kms_key_arn
  }

  tags = {
    Name = "hv-${var.environment}-${replace(var.ec2_instance_availability_zone, "-", "")}-data-services"
    OS   = "Linux"
  }

  # This runs the cloud-init config, copying the SSH key to the EC2 and running the startup.sh script.
  user_data                   = data.cloudinit_config.startup.rendered
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

output "dataservices-ip" {
  value = aws_instance.data_services.private_ip
}
