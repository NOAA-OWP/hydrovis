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
    volume_size = 200
    encrypted   = true
    kms_key_id  = var.kms_key_arn
    volume_type = "gp2"
  }

  user_data                   = data.cloudinit_config.startup.rendered
  user_data_replace_on_change = true
}

###############
## ARTIFACTS ##
###############

resource "aws_s3_object" "ingest_postgis_setup" {
  bucket = var.deployment_data_bucket
  key    = "terraform_artifacts/${path.module}/ingest/postgis_setup.sql"
  source = "${path.module}/data/ingest/postgis_setup.sql"
  source_hash = filemd5("${path.module}/data/ingest/postgis_setup.sql")
}

resource "aws_s3_object" "ingest_rfcfcst_base" {
  bucket = var.deployment_data_bucket
  key    = "terraform_artifacts/${path.module}/ingest/rfcfcst_base.sql.gz"
  source = "${path.module}/data/ingest/rfcfcst_base.sql.gz"
  source_hash = filemd5("${path.module}/data/ingest/rfcfcst_base.sql.gz")
}

resource "aws_s3_object" "ingest_ingest_users" {
  bucket  = var.deployment_data_bucket
  key     = "terraform_artifacts/${path.module}/ingest/ingest_users.sql"
  content = templatefile("${path.module}/data/ingest/ingest_users.sql.tftpl", {
              nwm_viz_ro_username       = jsondecode(var.nwm_viz_ro_secret_string)["username "]
              nwm_viz_ro_password       = jsondecode(var.nwm_viz_ro_secret_string)["password"]
              rfc_fcst_username          = jsondecode(var.rfc_fcst_secret_string)["username "]
              rfc_fcst_password         = jsondecode(var.rfc_fcst_secret_string)["password"]
              rfc_fcst_ro_user_username  = jsondecode(var.rfc_fcst_ro_user_secret_string)["username "]
              rfc_fcst_ro_user_password = jsondecode(var.rfc_fcst_ro_user_secret_string)["password"]
              rfc_fcst_user_username     = jsondecode(var.rfc_fcst_user_secret_string)["username "]
              rfc_fcst_user_password    = jsondecode(var.rfc_fcst_user_secret_string)["password"]
              location_ro_user_username = jsondecode(var.location_ro_user_secret_string)["username "]
              location_ro_user_password = jsondecode(var.location_ro_user_secret_string)["password"]
            })
  source_hash = filemd5("${path.module}/data/ingest/ingest_users.sql.tftpl")
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


data "aws_s3_object" "wrds_location3" {
  bucket = var.deployment_data_bucket
  key    = "location_db_dumps/wrds_location3.dump"
}

data "aws_s3_object" "egisDB_fim_catchments" {
  bucket = var.deployment_data_bucket
  key    = "viz_db_dumps/egisDB_fim_catchments.dump"
}

data "aws_s3_object" "egisDB_aep_fim" {
  bucket = var.deployment_data_bucket
  key    = "viz_db_dumps/egisDB_aep_fim.dump"
}

data "aws_s3_object" "egisDB_reference" {
  bucket = var.deployment_data_bucket
  key    = "viz_db_dumps/egisDB_reference.dump"
}

data "aws_s3_object" "egisDB_services" {
  bucket = var.deployment_data_bucket
  key    = "viz_db_dumps/egisDB_services.dump"
}

data "aws_s3_object" "vizDB_external" {
  bucket = var.deployment_data_bucket
  key    = "viz_db_dumps/vizDB_external.dump"
}

data "aws_s3_object" "vizDB_derived" {
  bucket = var.deployment_data_bucket
  key    = "viz_db_dumps/vizDB_derived.dump"
}

data "aws_s3_object" "vizDB_admin" {
  bucket = var.deployment_data_bucket
  key    = "viz_db_dumps/vizDB_admin.dump"
}

data "aws_s3_object" "vizDB_publish" {
  bucket = var.deployment_data_bucket
  key    = "viz_db_dumps/vizDB_publish.dump"
}

data "aws_s3_object" "vizDB_cache" {
  bucket = var.deployment_data_bucket
  key    = "viz_db_dumps/vizDB_cache.dump"
}

data "aws_s3_object" "vizDB_ingest" {
  bucket = var.deployment_data_bucket
  key    = "viz_db_dumps/vizDB_ingest.dump"
}

data "aws_s3_object" "vizDB_archive" {
  bucket = var.deployment_data_bucket
  key    = "viz_db_dumps/vizDB_archive.dump"
}


data "cloudinit_config" "startup" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/x-shellscript"
    filename     = "viz_postgresql_setup.sh"
    content      = templatefile("${path.module}/scripts/viz/postgresql_setup.sh.tftpl", {
      deployment_bucket          = var.data_deployment_bucket
      postgis_setup_s3_key       = aws_s3_object.ingest_postgis_setup.key
      viz_db_name                = var.viz_db_name
      viz_db_host                = var.viz_db_address
      viz_db_port                = var.viz_db_port
      viz_db_username            = jsondecode(var.viz_db_secret_string)["username"]
      viz_db_password            = jsondecode(var.viz_db_secret_string)["password"]
      egis_db_name               = var.egis_db_name
      egis_db_host               = var.egis_db_address
      egis_db_port               = var.egis_db_port
      egis_db_username           = jsondecode(var.egis_db_secret_string)["username"]
      egis_db_password           = jsondecode(var.egis_db_secret_string)["password"]
      location_db_name           = var.ingest_db_address
      location_db_host           = var.location_db_name
      location_db_port           = var.ingest_db_port
      location_db_username       = jsondecode(var.ingest_db_secret_string)["username"]
      location_db_password       = jsondecode(var.ingest_db_secret_string)["password"]
      viz_proc_admin_rw_username = jsondecode(var.viz_proc_admin_rw_secret_string)["username"]
      viz_proc_admin_rw_password = jsondecode(var.viz_proc_admin_rw_secret_string)["password"]
      viz_proc_dev_rw_username   = jsondecode(var.viz_proc_dev_rw_secret_string)["username"]
      viz_proc_dev_rw_password   = jsondecode(var.viz_proc_dev_rw_secret_string)["password"]

      
    })
  }

  part {
    content_type = "text/x-shellscript"
    filename     = "ingest_postgresql_setup.sh"
    content      = templatefile("${path.module}/scripts/ingest/postgresql_setup.sh.tftpl", {
      forecast_db_name     = var.forecast_db_name
      location_db_name     = var.location_db_name
      ingest_db_users      = local.ingest_db_users
      location_db_users    = local.location_db_users
      db_host              = var.ingest_db_address
      db_port              = var.ingest_db_port
      db_username          = jsondecode(var.ingest_db_secret_string)["username"]
      db_password          = jsondecode(var.ingest_db_secret_string)["password"]
      deployment_bucket    = var.data_deployment_bucket
      postgis_setup_s3_key = aws_s3_object.ingest_postgis_setup.key
      rfcfcst_base_s3_key  = aws_s3_object.ingest_rfcfcst_base.key
      ingest_user_s3_key   = aws_s3_object.ingest_ingest_users.key
    })
  }

  part {
    content_type = "text/x-shellscript"
    filename     = "rabbitmq_setup.sh"
    content      = templatefile("${path.module}/scripts/rabbitmq/rabbitmq_setup.sh.tftpl", {
      mq_ingest_endpoint = var.ingest_mq_endpoint
      mq_vhost           = local.mq_vhost[var.environment]
      mq_username        = jsondecode(var.ingest_mq_secret_string)["username"]
      mq_password        = jsondecode(var.ingest_mq_secret_string)["password"]
      rfcfcst_username   = jsondecode(var.rfc_fcst_user_secret_string)["username"]
      rfcfcst_password   = jsondecode(var.rfc_fcst_user_secret_string)["password"]
    })
  }
}
