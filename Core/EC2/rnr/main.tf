###############
## VARIABLES ##
###############

variable "ec2_instance_subnet" {
  type = string
}

variable "ec2_instance_availability_zone" {
  type = string
}

variable "ec2_instance_sgs" {
  type = list(string)
}

variable "environment" {
  description = "Hydrovis environment to be used for deployment"
  type        = string
}

variable "ami_owner_account_id" {
  type = string
}

variable "output_bucket" {
  description = "S3 bucket where the rnr outputs will be put"
  type        = string
}

variable "ec2_kms_key" {
  description = "KMS key to be used for ec2"
  type        = string
}

variable "ec2_instance_profile_name" {
  description = "iam profile name"
  type        = string
}

variable "dataservices_ip" {
  type = string
}

variable "deployment_data_bucket" {
  description = "S3 bucket where the deployment data lives"
  type        = string
}

variable "logstash_ip" {
  type = string
}

variable "dstore_url" {
  type = string
}

variable "nomads_url" {
  type = string
}

##################
## EC2 Instance ##
##################

resource "aws_instance" "replace_and_route" {
  ami                    = data.aws_ami.linux.id
  iam_instance_profile   = var.ec2_instance_profile_name
  instance_type          = "c5.2xlarge"
  availability_zone      = var.ec2_instance_availability_zone
  vpc_security_group_ids = var.ec2_instance_sgs
  subnet_id              = var.ec2_instance_subnet

  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    "Name" = "hv-${var.environment}-replace-route"
    "OS"   = "Linux"
  }

  root_block_device {
    encrypted  = true
    kms_key_id = var.ec2_kms_key
  }

  ebs_block_device {
    device_name = "/dev/sdf"
    volume_size = 100
    encrypted   = true
    kms_key_id  = var.ec2_kms_key
    tags = {
      "Name" = "hv-${var.environment}-replace-route-drive"
    }
  }

  user_data = data.cloudinit_config.startup.rendered
}


#################
## DATA BLOCKS ##
#################

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

data "template_file" "env_devel" {
  template = file("${path.module}/templates/.env.devel")
  vars = {
    OUTPUT_BUCKET = var.output_bucket
  }
}

data "template_file" "conus_ini_template" {
  template = file("${path.module}/templates/conus.ini.template")
  vars = {
    WRDS_HOST  = "http://${var.dataservices_ip}"
    DSTORE_URL = var.dstore_url
    NOMADS_URL = var.nomads_url
  }
}

data "template_file" "install" {
  template = file("${path.module}/templates/install.sh")
  vars = {
    DEPLOYMENT_DATA_BUCKET = var.deployment_data_bucket
    logstash_ip            = var.logstash_ip
  }
}

data "cloudinit_config" "startup" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/x-shellscript"
    filename     = "install.sh"
    content      = data.template_file.install.rendered
  }

  part {
    content_type = "text/cloud-config"
    filename     = "cloud-config.yaml"
    content = <<-END
      #cloud-config
      ${jsonencode({
    write_files = [
      {
        path        = "/deploy_files/conus.ini"
        permissions = "0400"
        owner       = "ec2-user:ec2-user"
        content     = data.template_file.conus_ini_template.rendered
      },
      {
        path        = "/deploy_files/.env.devel"
        permissions = "0400"
        owner       = "ec2-user:ec2-user"
        content     = data.template_file.env_devel.rendered
      }
    ]
})}
    END
}
}
