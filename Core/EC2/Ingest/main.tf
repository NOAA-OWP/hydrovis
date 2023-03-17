###############
## VARIABLES ##
###############

variable "environment" {
  description = "Hydrovis environment to be used for deployment"
  type        = string
}

variable "region" {
  type        = string
}

variable "ami_owner_account_id" {
  type        = string
}

variable "prc1_subnet" {
  type = string
}

variable "prc2_subnet" {
  type = string
}

variable "prc1_availability_zone" {
  type = string
}

variable "prc2_availability_zone" {
  type = string
}

variable "ec2_instance_sgs" {
  type = list(string)
}

variable "ec2_kms_key" {
  description = "KMS key to be used for ec2"
  type        = string
}

variable "ec2_instance_profile_name" {
  description = "iam profile name"
  type        = string
}

variable "deployment_bucket" {
  description = "S3 bucket where the deployment files reside"
  type        = string
}

variable "mq_ingest_endpoint" {
  type = string
}

variable "mq_ingest_secret_string" {
  type = string
}

variable "db_host" {
  type = string
}

variable "db_ingest_secret_string" {
  type = string
}


locals {
  user_data = templatefile("${path.module}/templates/prc_install.sh.tftpl", {
    deployment_bucket   = var.deployment_bucket
    hml_ingester_s3_key = aws_s3_object.hml_ingester.key
    environment         = var.environment
    r_host              = split(":", split("/", var.mq_ingest_endpoint)[2])[0]
    r_password          = jsondecode(var.mq_ingest_secret_string)["password"]
    db_host             = var.db_host
    db_password         = jsondecode(var.db_ingest_secret_string)["password"]
  })
}

###############
## ARTIFACTS ##
###############

resource "aws_s3_object" "hml_ingester" {
  bucket      = var.deployment_bucket
  key         = "terraform_artifacts/${path.module}/owp-hml-ingester.tar.gz"
  source      = "${path.module}/owp-hml-ingester.tar.gz"
  source_hash = filemd5("${path.module}/owp-hml-ingester.tar.gz")
}

#################
## DATA BLOCKS ##
#################

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
  owners = [var.ami_owner_account_id]
}

##################
## EC2 Instance ##
##################

resource "aws_instance" "ingest_prc1" {
  ami                    = data.aws_ami.linux.id
  iam_instance_profile   = var.ec2_instance_profile_name
  instance_type          = "t2.small"
  availability_zone      = var.prc1_availability_zone
  vpc_security_group_ids = var.ec2_instance_sgs
  subnet_id              = var.prc1_subnet
  key_name               = "hv-${var.environment}-ec2-key-pair-${var.region}"

  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    "Name" = "hv-vpp-${var.environment}-data-ingest-1"
    "OS"   = "Linux"
  }

  root_block_device {
    volume_size = 30
    encrypted   = true
    kms_key_id  = var.ec2_kms_key
    volume_type = "gp2"
  }

  user_data                   = local.user_data
  user_data_replace_on_change = true
}

resource "aws_instance" "ingest_prc2" {
  ami                    = data.aws_ami.linux.id
  iam_instance_profile   = var.ec2_instance_profile_name
  instance_type          = "t2.small"
  availability_zone      = var.prc2_availability_zone
  vpc_security_group_ids = var.ec2_instance_sgs
  subnet_id              = var.prc2_subnet
  key_name               = "hv-${var.environment}-ec2-key-pair-${var.region}"

  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    "Name" = "hv-vpp-${var.environment}-data-ingest-2"
    "OS"   = "Linux"
  }

  root_block_device {
    volume_size = 30
    encrypted   = true
    kms_key_id  = var.ec2_kms_key
    volume_type = "gp2"
  }

  user_data                   = local.user_data
  user_data_replace_on_change = true
}
