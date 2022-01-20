###############
## VARIABLES ##
###############

variable "ami_owner_account_id" {
  type = string
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
  description = "iam profile name"
  type        = string
}

variable "environment" {
  description = "Hydrovis environment to be used for deployment"
  type        = string
}

variable "kms_key_arn" {
  type = string
}

variable "db_ingest_secret_string" {
  type = string
}

variable "db_ingest_address" {
  type = string
}

variable "db_ingest_port" {
  type = string
}
variable "data_deployment_bucket" {
  type = string
}

variable "mq_ingest_secret_string" {
  type = string
}

variable "mq_ingest_endpoint" {
  type = string
}

variable "nwm_viz_ro_secret_string" {
  type = string
}

variable "rfc_fcst_secret_string" {
  type = string
}

variable "rfc_fcst_ro_user_secret_string" {
  type = string
}

variable "rfc_fcst_user_secret_string" {
  type = string
}

variable "location_ro_user_secret_string" {
  type = string
}

locals {
  rfc_db_users              = "rfc_fcst, rfc_fcst_ro"
  location_db_users         = "rfc_fcst_ro, location_ro_user_grp"
  forecast_db               = "rfcfcst"
  location_db               = "wrds_location3"
  nwm_viz_ro_password       = jsondecode(var.nwm_viz_ro_secret_string)["password"]
  rfc_fcst_password         = jsondecode(var.rfc_fcst_secret_string)["password"]
  rfc_fcst_ro_user_password = jsondecode(var.rfc_fcst_ro_user_secret_string)["password"]
  rfc_fcst_user_password    = jsondecode(var.rfc_fcst_user_secret_string)["password"]
  location_ro_user_password = jsondecode(var.location_ro_user_secret_string)["password"]

  mq_vhost = {
    "dev" : "development",
    "development" : "development",
    "ti" : "testing_integration",
    "uat" : "user_acceptance_testing",
    "prod" : "production",
    "production" : "production",
  }
}

##################
## EC2 Instance ##
##################

resource "aws_instance" "rds-bastion" {
  ami                    = data.aws_ami.linux.id
  iam_instance_profile   = var.ec2_instance_profile_name
  instance_type          = "m1.small"
  availability_zone      = var.ec2_instance_availability_zone
  vpc_security_group_ids = var.ec2_instance_sgs
  subnet_id              = var.ec2_instance_subnet

  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    "Name" = "hv-${var.environment}-${var.ec2_instance_availability_zone}-rds-l-dba-1"
    "OS"   = "Linux"
  }

  root_block_device {
    volume_size = 12
    encrypted   = true
    kms_key_id  = var.kms_key_arn
    volume_type = "gp2"
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

data "template_file" "postgresql_setup" {
  template = file("${path.module}/templates/postgres/postgresql_setup.sh")
  vars = {
    FORECASTDB        = local.forecast_db
    LOCATIONDB        = local.location_db
    RFCDBUSERS        = local.rfc_db_users
    LOCATIONDBUSERS   = local.location_db_users
    PGHOST            = var.db_ingest_address
    PGPORT            = var.db_ingest_port
    PGUSERNAME        = jsondecode(var.db_ingest_secret_string)["username"]
    PGPASSWORD        = jsondecode(var.db_ingest_secret_string)["password"]
    DEPLOYMENT_BUCKET = var.data_deployment_bucket

    INITIALIZATION_SCRIPT = "${file("${path.module}/templates/postgres/postgresql_initialization.sh")}"
  }
}

data "template_file" "db_users" {
  template = file("${path.module}/templates/postgres/db_users.sql")
  vars = {
    NWM_VIZ_RO       = local.nwm_viz_ro_password
    RFC_FCST         = local.rfc_fcst_password
    RFC_FCST_RO_USER = local.rfc_fcst_ro_user_password
    RFC_FCST_USER    = local.rfc_fcst_user_password
    LOCATION_RO_USER = local.location_ro_user_password
  }
}

data "template_file" "rabbitmq_setup" {
  template = file("${path.module}/templates/rabbitmq/rabbitmq_setup.sh")
  vars = {
    MQINGESTENDPOINT       = var.mq_ingest_endpoint
    MQUSERNAME             = jsondecode(var.mq_ingest_secret_string)["username"]
    MQPASSWORD             = jsondecode(var.mq_ingest_secret_string)["password"]
    RFC_FCST_USER          = jsondecode(var.rfc_fcst_user_secret_string)["username"]
    RFC_FCST_USER_PASSWORD = jsondecode(var.rfc_fcst_user_secret_string)["password"]
    MQVHOST                = local.mq_vhost[var.environment]

    INITIALIZATION_SCRIPT = "${file("${path.module}/templates/rabbitmq/rabbitmq_initialization.sh")}"
  }
}

data "cloudinit_config" "startup" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/x-shellscript"
    filename     = "postgres_setup.sh"
    content      = data.template_file.postgresql_setup.rendered
  }

  part {
    content_type = "text/x-shellscript"
    filename     = "rabbitmq_setup.sh"
    content      = data.template_file.rabbitmq_setup.rendered
  }

  part {
    content_type = "text/cloud-config"
    filename     = "cloud-config.yaml"
    content = <<-END
      #cloud-config
      ${jsonencode({
    write_files = [
      {
        path        = "/deploy_files/db_users.sql"
        permissions = "0400"
        owner       = "ec2-user:ec2-user"
        content     = data.template_file.db_users.rendered
      }
    ]
})}
    END
}
}

output "forecast_db" {
  value = local.forecast_db
}

output "location_db" {
  value = local.location_db
}
