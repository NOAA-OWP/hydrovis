###############
## Variables ##
###############

variable "environment" {
  description = "Hydrovis environment"
  type        = string
}

variable "account_id" {
  type        = string
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

variable "private_route_53_zone" {
  type = object({
    name     = string
    zone_id  = string
  })
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
  key_name               = "hv-${var.environment}-ec2-key-pair-${var.region}"

  #root disk
  root_block_device {
    volume_size           = "200"
    volume_type           = "gp2"
    encrypted             = true
    kms_key_id            = var.ec2_kms_key
    delete_on_termination = true
  }

  user_data                   = data.cloudinit_config.licensemanager.rendered
  user_data_replace_on_change = true

  lifecycle {
    ignore_changes = [ami, tags]
  }

  tags = {
    Name = "hv-vpp-${var.environment}-egis-license-manager"
    OS   = "Windows"
  }
}

resource "aws_route53_record" "hydrovis" {
  zone_id = var.private_route_53_zone.zone_id
  name    = "egis-license-manager.${var.private_route_53_zone.name}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.license_manager.private_ip]
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
  owners = [var.account_id]
}

data "cloudinit_config" "licensemanager" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/x-shellscript"
    filename     = "ArcGIS_LM_Setup.ps1"
    content      = templatefile("${path.module}/templates/ArcGIS_LM_Setup.ps1.tftpl", {
      environment = var.environment
      region      = var.region
    })
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

output "dns_name" {
  value = aws_route53_record.hydrovis.name
}