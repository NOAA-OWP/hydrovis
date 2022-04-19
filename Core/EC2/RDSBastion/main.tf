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

variable "viz_db_name" {
  type = string
}

variable "egis_db_secret_string" {
  type = string
}

variable "egis_db_address" {
  type = string
}

variable "egis_db_port" {
  type = string
}

variable "egis_db_name" {
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

variable "viz_proc_dev_rw_secret_string" {
  type = string
}

variable "fim_version" {
  type = string
}

variable "forecast_db_name" {
  type = string
}

variable "location_db_name" {
  type = string
}

locals {
  ingest_db_users             = "rfc_fcst, rfc_fcst_ro"
  location_db_users           = "rfc_fcst_ro, location_ro_user_grp"
  viz_db_users                = "viz_proc_admin_rw_user"
  home_dir                    = "/home/ec2-user"

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
  instance_type          = "m5.large"
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
    volume_size = 60
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

data "cloudinit_config" "startup" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/x-shellscript"
    filename     = "viz_postgresql_setup.sh"
    content      = templatefile("${path.module}/scripts/viz/postgresql_setup.sh.tftpl", {
      VIZDBNAME              = var.viz_db_name
      VIZDBHOST              = var.viz_db_address
      VIZDBPORT              = var.viz_db_port
      VIZDBUSERNAME          = jsondecode(var.viz_db_secret_string)["username"]
      VIZDBPASSWORD          = jsondecode(var.viz_db_secret_string)["password"]
      EGISDBNAME             = var.egis_db_name
      EGISDBHOST             = var.egis_db_address
      EGISDBPORT             = var.egis_db_port
      EGISDBUSERNAME         = jsondecode(var.egis_db_secret_string)["username"]
      EGISDBPASSWORD         = jsondecode(var.egis_db_secret_string)["password"]
      DEPLOYMENT_BUCKET      = var.data_deployment_bucket
      HOME                   = local.home_dir
      VIZ_PROC_ADMIN_RW_USER = jsondecode(var.viz_proc_admin_rw_secret_string)["username"]
      VIZ_PROC_ADMIN_RW_PASS = jsondecode(var.viz_proc_admin_rw_secret_string)["password"]
      VIZ_PROC_DEV_RW_USER   = jsondecode(var.viz_proc_dev_rw_secret_string)["username"]
      VIZ_PROC_DEV_RW_PASS   = jsondecode(var.viz_proc_dev_rw_secret_string)["password"]
    })
  }

  part {
    content_type = "text/x-shellscript"
    filename     = "ingest_postgresql_setup.sh"
    content      = templatefile("${path.module}/scripts/ingest/postgresql_setup.sh.tftpl", {
      FORECASTDB        = var.forecast_db_name
      LOCATIONDB        = var.location_db_name
      INGESTDBUSERS     = local.ingest_db_users
      LOCATIONDBUSERS   = local.location_db_users
      DBHOST            = var.ingest_db_address
      DBPORT            = var.ingest_db_port
      DBUSERNAME        = jsondecode(var.ingest_db_secret_string)["username"]
      DBPASSWORD        = jsondecode(var.ingest_db_secret_string)["password"]
      DEPLOYMENT_BUCKET = var.data_deployment_bucket
    })
  }

  part {
    content_type = "text/x-shellscript"
    filename     = "rabbitmq_setup.sh"
    content      = templatefile("${path.module}/scripts/rabbitmq/rabbitmq_setup.sh.tftpl", {
      MQINGESTENDPOINT       = var.ingest_mq_endpoint
      MQUSERNAME             = jsondecode(var.ingest_mq_secret_string)["username"]
      MQPASSWORD             = jsondecode(var.ingest_mq_secret_string)["password"]
      RFC_FCST_USER          = jsondecode(var.rfc_fcst_user_secret_string)["username"]
      RFC_FCST_USER_PASSWORD = jsondecode(var.rfc_fcst_user_secret_string)["password"]
      MQVHOST                = local.mq_vhost[var.environment]
    })
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
            content     = templatefile("${path.module}/scripts/ingest/ingest_users.sql.tftpl", {
              NWM_VIZ_RO       = jsondecode(var.nwm_viz_ro_secret_string)["password"]
              RFC_FCST         = jsondecode(var.rfc_fcst_secret_string)["password"]
              RFC_FCST_RO_USER = jsondecode(var.rfc_fcst_ro_user_secret_string)["password"]
              RFC_FCST_USER    = jsondecode(var.rfc_fcst_user_secret_string)["password"]
              LOCATION_RO_USER = jsondecode(var.location_ro_user_secret_string)["password"]
            })
          }
        ]
      })}
    END
  }
}
