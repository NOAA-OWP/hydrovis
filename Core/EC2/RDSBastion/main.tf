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

variable "ingest_db_secret_string" {
  type = string
}

variable "ingest_db_address" {
  type = string
}

variable "ingest_db_port" {
  type = string
}

variable "viz_db_secret_string" {
  type = string
}

variable "viz_db_address" {
  type = string
}

variable "viz_db_port" {
  type = string
}

variable "data_deployment_bucket" {
  type = string
}

variable "ingest_mq_secret_string" {
  type = string
}

variable "ingest_mq_endpoint" {
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

variable "viz_proc_admin_rw_secret_string" {
  type = string
}

locals {
  ingest_db_users            = "rfc_fcst, rfc_fcst_ro"
  location_db_users          = "rfc_fcst_ro, location_ro_user_grp"
  viz_db_users               = "viz_proc_admin_rw_user"
  forecast_db                = "rfcfcst"
  location_db                = "wrds_location3"
  viz_db                     = "vizprocessing"
  nwm_viz_ro_password        = jsondecode(var.nwm_viz_ro_secret_string)["password"]
  rfc_fcst_password          = jsondecode(var.rfc_fcst_secret_string)["password"]
  rfc_fcst_ro_user_password  = jsondecode(var.rfc_fcst_ro_user_secret_string)["password"]
  rfc_fcst_user_password     = jsondecode(var.rfc_fcst_user_secret_string)["password"]
  location_ro_user_password  = jsondecode(var.location_ro_user_secret_string)["password"]
  viz_proc_admin_rw_password = jsondecode(var.viz_proc_admin_rw_secret_string)["password"]
  home_dir                   = "/home/ec2-user"

  mq_vhost = {
    "dev" : "development",
    "development" : "development",
    "ti" : "testing_integration",
    "uat" : "user_acceptance-testing",
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

data "template_file" "ingest_postgresql_setup" {
  template = file("${path.module}/scripts/ingest/postgresql_setup.sh")
  vars = {
    FORECASTDB        = local.forecast_db
    LOCATIONDB        = local.location_db
    INGESTDBUSERS     = local.ingest_db_users
    LOCATIONDBUSERS   = local.location_db_users
    DBHOST            = var.ingest_db_address
    DBPORT            = var.ingest_db_port
    DBUSERNAME        = jsondecode(var.ingest_db_secret_string)["username"]
    DBPASSWORD        = jsondecode(var.ingest_db_secret_string)["password"]
    DEPLOYMENT_BUCKET = var.data_deployment_bucket
  }
}

data "template_file" "ingest_users" {
  template = file("${path.module}/scripts/ingest/ingest_users.sql")
  vars = {
    NWM_VIZ_RO       = local.nwm_viz_ro_password
    RFC_FCST         = local.rfc_fcst_password
    RFC_FCST_RO_USER = local.rfc_fcst_ro_user_password
    RFC_FCST_USER    = local.rfc_fcst_user_password
    LOCATION_RO_USER = local.location_ro_user_password
  }
}

data "template_file" "rabbitmq_setup" {
  template = file("${path.module}/scripts/rabbitmq/rabbitmq_setup.sh")
  vars = {
    MQINGESTENDPOINT       = var.ingest_mq_endpoint
    MQUSERNAME             = jsondecode(var.ingest_mq_secret_string)["username"]
    MQPASSWORD             = jsondecode(var.ingest_mq_secret_string)["password"]
    RFC_FCST_USER          = jsondecode(var.rfc_fcst_user_secret_string)["username"]
    RFC_FCST_USER_PASSWORD = jsondecode(var.rfc_fcst_user_secret_string)["password"]
    MQVHOST                = local.mq_vhost[var.environment]
  }
}

data "template_file" "viz_postgresql_setup" {
  template = file("${path.module}/scripts/viz/postgresql_setup.sh")
  vars = {
    DBNAME            = local.viz_db
    DBHOST            = var.viz_db_address
    DBPORT            = var.viz_db_port
    DBUSERNAME        = jsondecode(var.viz_db_secret_string)["username"]
    DBPASSWORD        = jsondecode(var.viz_db_secret_string)["password"]
    DEPLOYMENT_BUCKET = var.data_deployment_bucket
    DBUSERS           = local.viz_db_users
    HOME              = local.home_dir
  }
}

data "template_file" "viz_setup" {
  template = file("${path.module}/scripts/viz/viz_setup.sql")
  vars = {
    VIZ_PROC_ADMIN_RW_PASS = local.viz_proc_admin_rw_password
    RECURR_FLOW_CONUS      = "rf_2_0_17c"
    RECURR_FLOW_HI         = "rf_2_0"
    RECURR_FLOW_PRVI       = "rf_2_0"
    HOME                   = local.home_dir
  }
}

data "cloudinit_config" "startup" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/x-shellscript"
    filename     = "ingest_postgresql_setup.sh"
    content      = data.template_file.ingest_postgresql_setup.rendered
  }

  part {
    content_type = "text/x-shellscript"
    filename     = "rabbitmq_setup.sh"
    content      = data.template_file.rabbitmq_setup.rendered
  }

  part {
    content_type = "text/x-shellscript"
    filename     = "viz_postgresql_setup.sh"
    content      = data.template_file.viz_postgresql_setup.rendered
  }

  part {
    content_type = "text/cloud-config"
    filename     = "cloud-config.yaml"
    content = <<-END
      #cloud-config
      ${jsonencode({
    write_files = [
      {
        path        = "/deploy_files/ingest_users.sql"
        permissions = "0400"
        owner       = "ec2-user:ec2-user"
        content     = data.template_file.ingest_users.rendered
      },
      {
        path        = "/deploy_files/viz_setup.sql"
        permissions = "0400"
        owner       = "ec2-user:ec2-user"
        content     = data.template_file.viz_setup.rendered
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

output "viz_db" {
  value = local.viz_db
}
