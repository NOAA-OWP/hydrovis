###############
## Variables ##
###############

variable "environment" {
  description = "Hydrovis environment"
  type        = string
}

variable "ami_owner_account_id" {
  type        = string
}

variable "region" {
  description = "Hydrovis region"
  type        = string
}

variable "ec2_instance_sgs" {
  type = list(string)
}

variable "ec2_instance_subnet" {
  type = string
}

variable "ec2_instance_availability_zone" {
  type = string
}

variable "ec2_instance_profile_name" {
  description = "iam profile name"
  type        = string
}

variable "ec2_kms_key" {
  description = "KMS key to be used for ec2"
  type        = string
}

##################
## EC2 Instance ##
##################

resource "aws_instance" "arcgismonitor" {
  ami                    = data.aws_ami.windows.id
  instance_type          = "m5.xlarge"
  vpc_security_group_ids = var.ec2_instance_sgs
  subnet_id              = var.ec2_instance_subnet
  availability_zone      = var.ec2_instance_availability_zone
  iam_instance_profile   = var.ec2_instance_profile_name
  key_name               = "hv-${var.environment}-ec2-key-pair-${var.region}"

  #root disk
  root_block_device {
    volume_size           = "200"
    volume_type           = "gp2"
    encrypted             = true
    kms_key_id            = var.ec2_kms_key
    delete_on_termination = true
  }

  user_data                   = data.cloudinit_config.arcgismonitor.rendered
  user_data_replace_on_change = true

  lifecycle {
    ignore_changes = [ami, tags]
  }

  tags = {
    Name = "hv-vpp-${var.environment}-egis-monitor"
    OS   = "Windows"
  }
}

#################
## Data Blocks ##
#################

data "aws_ami" "windows" {
  most_recent = true
  filter {
    name   = "name"
    values = ["windows-server-2019-awscli-git-pgadmin-arcgis-stig*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = [var.ami_owner_account_id]
}

data "cloudinit_config" "arcgismonitor" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/x-shellscript"
    filename     = "ArcGIS_LM_Setup.ps1"
    content      = templatefile("${path.module}/templates/ArcGIS_Monitor_Setup.ps1.tftpl", {
      environment = var.environment
      region      = var.region
    })
  }
}
#################################################################################################################################
## Admin will have to login and install/run post-instatll for ArcGIS Monitor. Monitor will have to be manully configured ##
#################################################################################################################################
