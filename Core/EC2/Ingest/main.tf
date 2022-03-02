###############
## VARIABLES ##
###############

variable "environment" {
  description = "Hydrovis environment to be used for deployment"
  type        = string
}

variable "ami_owner_account_id" {
  type = string
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

variable "deployment_data_bucket" {
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

variable "logstash_ip" {
  type = string
}

locals {
  hvl_environment = var.environment == "ti" ? "TI" : var.environment == "uat" ? "UAT" : var.environment
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

  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    "Name" = "hv-${var.environment}-ing-l-prc-1"
    "OS"   = "Linux"
  }

  root_block_device {
    volume_size = 30
    encrypted   = true
    kms_key_id  = var.ec2_kms_key
    volume_type = "gp2"
  }

  user_data = data.template_file.prc_install.rendered
}

resource "aws_instance" "ingest_prc2" {
  ami                    = data.aws_ami.linux.id
  iam_instance_profile   = var.ec2_instance_profile_name
  instance_type          = "t2.small"
  availability_zone      = var.prc2_availability_zone
  vpc_security_group_ids = var.ec2_instance_sgs
  subnet_id              = var.prc2_subnet

  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    "Name" = "hv-${var.environment}-ing-l-prc-2"
    "OS"   = "Linux"
  }

  root_block_device {
    volume_size = 30
    encrypted   = true
    kms_key_id  = var.ec2_kms_key
    volume_type = "gp2"
  }

  user_data = data.template_file.prc_install.rendered
}

####################
## TEMPLATE FILES ##
####################

data "template_file" "prc_install" {
  template = file("${path.module}/templates/prc_install.sh")
  vars = {
    DEPLOYMENT_DATA_BUCKET = var.deployment_data_bucket
    HVLEnvironment         = local.hvl_environment
    RSCHEME                = split(":", var.mq_ingest_endpoint)[0]
    RPORT                  = split(":", var.mq_ingest_endpoint)[2]
    RHOST                  = split(":", split("/", var.mq_ingest_endpoint)[2])[0]
    MQINGESTPASSWORD       = jsondecode(var.mq_ingest_secret_string)["password"]
    DBHOST                 = var.db_host
    DBPASSWORD             = jsondecode(var.db_ingest_secret_string)["password"]
    HVLEnvironment         = var.environment
    logstash_ip            = var.logstash_ip
  }
}