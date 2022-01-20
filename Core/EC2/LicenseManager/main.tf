###############
## Variables ##
###############

variable "environment" {
  description = "Hydrovis environment"
  type        = string
}

variable "ami_owner_account_id" {
  type = string
}

variable "region" {
  description = "Hydrovis region"
  type        = string
}

variable "ec2_instance_availability_zone" {
  type = string
}

variable "ec2_instance_sgs" {
  type = list(string)
}

variable "ec2_instance_subnet" {
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

resource "aws_instance" "license_manager" {
  ami                    = data.aws_ami.windows.id
  instance_type          = "m5.large"
  vpc_security_group_ids = var.ec2_instance_sgs
  subnet_id              = var.ec2_instance_subnet
  iam_instance_profile   = var.ec2_instance_profile_name
  key_name               = "hv-${var.environment}-ec2-key-pair"

  #root disk
  root_block_device {
    volume_size           = "200"
    volume_type           = "gp2"
    encrypted             = true
    kms_key_id            = var.ec2_kms_key
    delete_on_termination = true
  }

  user_data = data.template_cloudinit_config.licensemanager.rendered

  lifecycle {
    ignore_changes = [ami, tags]
  }

  tags = {
    Name = "hv-${var.environment}-egis-ArcGIS-LicenseManager"
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
    values = ["hydrovis-win2019-STIG*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = [var.ami_owner_account_id]
}

data "template_file" "licensemanager" {
  template = file("${path.module}/templates/ArcGIS_LM_Setup.ps1")
  vars = {
    environment = var.environment
    region      = var.region
  }
}

data "template_cloudinit_config" "licensemanager" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/x-shellscript"
    filename     = "ArcGIS_LM_Setup.ps1"
    content      = data.template_file.licensemanager.rendered
  }
}
#######################################################################################################################################
# After the machine is created log on to the machine and 																			  #
# double click C:\LicenseManager\ArcGISProAdvanced_ConcurrentUse_1055467.prvs to authorize the licenses. (accecpt all defaults)		  #
# 																																	  #
#######################################################################################################################################

#############
## Outputs ##
#############

output "license_manager_ip" {
  value = aws_instance.license_manager.private_ip
}
