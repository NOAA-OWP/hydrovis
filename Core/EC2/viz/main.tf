#######################
## DYNAMIC VARIABLES ##
#######################
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

variable "ec2_instance_availability_zone" {
  type = string
}

variable "ec2_instance_sgs" {
  type = list(string)
}

variable "ec2_instance_subnet" {
  type = string
}

variable "dataservices_ip" {
  type = string
}

variable "license_server_ip" {
  type = string
}

variable "nwm_data_bucket" {
  description = "S3 bucket for NWM data"
  type        = string
}

variable "fim_data_bucket" {
  description = "S3 bucket for fim data"
  type        = string
}

variable "fim_output_bucket" {
  description = "S3 bucket where the FIM processing outputs will live."
  type        = string
}

variable "nwm_max_flows_data_bucket" {
  description = "S3 bucket for NWM max flows data"
  type        = string
}

variable "rnr_max_flows_data_bucket" {
  description = "S3 bucket for RnR max flows data"
  type        = string
}

variable "deployment_data_bucket" {
  description = "S3 bucket where the visualization static data lives"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key to be used for ec2"
  type        = string
}

variable "ec2_instance_profile_name" {
  description = "iam profile name"
  type        = string
}

variable "fim_version" {
  description = "FIM version to run"
  type        = string
}

variable "windows_service_status" {
  description = "Argument for if windows services for pipelines should stop or start on machine spinup"
  type        = string

  validation {
    condition     = contains(["start", "stop"], var.windows_service_status)
    error_message = "Valid values for var: windows_service_status are (start, stop)."
  }
}

variable "windows_service_startup" {
  description = "Argument for if windows services for pipelines should start automatically or manually on machine reboot"
  type        = string

  validation {
    condition     = contains(["SERVICE_AUTO_START", "SERVICE_DEMAND_START"], var.windows_service_startup)
    error_message = "Valid values for var: windows_service_startup are (SERVICE_AUTO_START, SERVICE_DEMAND_START)."
  }
}

variable "pipeline_user_secret_string" {
  type = string
}

variable "hydrovis_egis_pass" {
  type = string
}

variable "vlab_repo_prefix" {
  type = string
}

variable "vlab_host" {
  type = string
}

variable "github_repo_prefix" {
  type = string
}

variable "github_host" {
  type = string
}

variable "viz_db_host" {
  type = string
}

variable "viz_db_name" {
  type = string
}

variable "viz_db_user_secret_string" {
  type = string
}

variable "egis_db_host" {
  type = string
}

variable "egis_db_name" {
  type = string
}

variable "egis_db_secret_string" {
  type = string
}

data "aws_caller_identity" "current" {}

locals {
  egis_host          = var.environment == "prod" ? "maps.water.noaa.gov" : var.environment == "uat" ? "maps-staging.water.noaa.gov" : var.environment == "ti" ? "maps-testing.water.noaa.gov" : "hydrovis-dev.nwc.nws.noaa.gov"
  deploy_file_prefix = "viz/"
}


##############
## TF SETUP ##
##############

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

################
## S3 Uploads ##
################

resource "aws_s3_object" "setup_upload" {
  bucket      = var.deployment_data_bucket
  key         = "viz/viz_ec2_setup.ps1"
  source      = "${path.module}/scripts/viz_ec2_setup.ps1"
  source_hash = filemd5("${path.module}/scripts/viz_ec2_setup.ps1")
}

#################
## Data Blocks ##
#################

data "cloudinit_config" "pipeline_setup" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/x-shellscript"
    filename     = "prc_setup.ps1"
    content      = templatefile("${path.module}/templates/prc_setup.ps1.tftpl", {
      Fileshare_IP                   = "\\\\${aws_instance.viz_fileshare.private_ip}"
      EGIS_HOST                      = local.egis_host
      VIZ_ENVIRONMENT                = var.environment
      FIM_VERSION                    = var.fim_version
      VLAB_SSH_KEY_CONTENT           = file("${path.root}/sensitive/viz/vlab")
      GITHUB_SSH_KEY_CONTENT         = file("${path.root}/sensitive/viz/github")
      LICENSE_REG_CONTENT            = templatefile("${path.module}/templates/pro_license.reg.tftpl", {
        LICENSE_SERVER = var.license_server_ip
        PIPELINE_USER  = jsondecode(var.pipeline_user_secret_string)["username"]
      })
      FILEBEAT_YML_CONTENT           = templatefile("${path.module}/templates/filebeat.yml.tftpl", {})
      WRDS_HOST                      = var.dataservices_ip
      NWM_DATA_BUCKET                = var.nwm_data_bucket
      FIM_DATA_BUCKET                = var.fim_data_bucket
      FIM_OUTPUT_BUCKET              = var.fim_output_bucket
      NWM_MAX_FLOWS_DATA_BUCKET      = var.nwm_max_flows_data_bucket
      RNR_MAX_FLOWS_DATA_BUCKET      = var.rnr_max_flows_data_bucket
      DEPLOYMENT_DATA_BUCKET         = var.deployment_data_bucket
      DEPLOYMENT_DATA_OBJECT         = aws_s3_object.setup_upload.key
      DEPLOY_FILES_PREFIX            = local.deploy_file_prefix
      WINDOWS_SERVICE_STATUS         = var.windows_service_status
      WINDOWS_SERVICE_STARTUP        = var.windows_service_startup
      PIPELINE_USER                  = jsondecode(var.pipeline_user_secret_string)["username"]
      PIPELINE_USER_ACCOUNT_PASSWORD = jsondecode(var.pipeline_user_secret_string)["password"]
      HYDROVIS_EGIS_PASS             = var.hydrovis_egis_pass
      VLAB_REPO_PREFIX               = var.vlab_repo_prefix
      VLAB_HOST                      = var.vlab_host
      GITHUB_REPO_PREFIX             = var.github_repo_prefix
      GITHUB_HOST                    = var.github_host
      VIZ_DB_HOST                    = var.viz_db_host
      VIZ_DB_DATABASE                = var.viz_db_name
      VIZ_DB_USERNAME                = jsondecode(var.viz_db_user_secret_string)["username"]
      VIZ_DB_PASSWORD                = jsondecode(var.viz_db_user_secret_string)["password"]
      EGIS_DB_HOST                   = var.egis_db_host
      EGIS_DB_DATABASE               = var.egis_db_name
      EGIS_DB_USERNAME               = jsondecode(var.egis_db_secret_string)["username"]
      EGIS_DB_PASSWORD               = jsondecode(var.egis_db_secret_string)["password"]
      AWS_REGION                     = var.region
    })
  }
}

##################
## VIZ PIPELINE ##
##################

resource "aws_instance" "viz_pipeline" {
  ami                    = data.aws_ami.windows.id
  iam_instance_profile   = var.ec2_instance_profile_name
  instance_type          = "m5.xlarge"
  availability_zone      = var.ec2_instance_availability_zone
  vpc_security_group_ids = var.ec2_instance_sgs
  subnet_id              = var.ec2_instance_subnet
  key_name               = "hv-${var.environment}-ec2-key-pair"

  lifecycle {
    ignore_changes = [ami, tags]
  }

  tags = {
    "Name" = "hv-${var.environment}-viz-prc-1"
    "OS"   = "Windows"
  }

  root_block_device {
    encrypted   = true
    kms_key_id  = var.kms_key_arn
    volume_size = 150
  }

  ebs_block_device {
    device_name = "xvdf"
    volume_size = 1000
    encrypted   = true
    kms_key_id  = var.kms_key_arn
    tags = {
      "Name" = "hv-${var.environment}-viz-prc-drive"
    }
  }

  user_data                   = data.cloudinit_config.pipeline_setup.rendered
  user_data_replace_on_change = true
}


###################
## VIZ FILESHARE ##
###################

data "cloudinit_config" "fileshare_setup" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/x-shellscript"
    filename     = "fs_setup.ps1"
    content      = templatefile("${path.module}/templates/fs_setup.ps1.tftpl", {
      PIPELINE_USER = jsondecode(var.pipeline_user_secret_string)["username"]
    })
  }
}

resource "aws_instance" "viz_fileshare" {
  ami                    = data.aws_ami.windows.id
  iam_instance_profile   = var.ec2_instance_profile_name
  instance_type          = "m5.large"
  availability_zone      = var.ec2_instance_availability_zone
  vpc_security_group_ids = var.ec2_instance_sgs
  subnet_id              = var.ec2_instance_subnet
  key_name               = "hv-${var.environment}-ec2-key-pair"

  lifecycle {
    ignore_changes = [ami, tags]
  }

  tags = {
    "Name" = "hv-${var.environment}-viz-fileshare"
    "OS"   = "Windows"
  }

  root_block_device {
    encrypted   = true
    kms_key_id  = var.kms_key_arn
    volume_size = 150
  }

  ebs_block_device {
    device_name = "xvdf"
    volume_size = 1000
    encrypted   = true
    kms_key_id  = var.kms_key_arn
    tags = {
      "Name" = "hv-${var.environment}-viz-fs-drive"
    }
  }

  user_data = data.cloudinit_config.fileshare_setup.rendered
}