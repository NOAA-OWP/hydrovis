#######################
## DYNAMIC VARIABLES ##
#######################
variable "environment" {
  description = "Hydrovis environment"
  type        = string
}

variable "account_id" {
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

variable "license_server_host" {
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

variable "python_preprocessing_bucket" {
  description = "S3 bucket for NWM max flows data"
  type        = string
}

variable "rnr_data_bucket" {
  description = "S3 bucket for RnR output data"
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

variable "private_route_53_zone" {
  type = object({
    name    = string
    zone_id = string
  })
}

variable "nwm_dataflow_version" {
  type = string
}

data "aws_caller_identity" "current" {}

locals {
  egis_host = var.environment == "prod" ? "maps.water.noaa.gov" : var.environment == "uat" ? "maps-staging.water.noaa.gov" : var.environment == "ti" ? "maps-testing.water.noaa.gov" : "hydrovis-dev.nwc.nws.noaa.gov"
}


##############
## TF SETUP ##
##############

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

################
## S3 Uploads ##
################

resource "aws_s3_object" "setup_upload" {
  provider = aws.no_tags
  
  bucket      = var.deployment_data_bucket
  key         = "terraform_artifacts/${path.module}/scripts/viz_ec2_setup.ps1"
  source      = "${path.module}/scripts/viz_ec2_setup.ps1"
  source_hash = filemd5("${path.module}/scripts/viz_ec2_setup.ps1")
}

#################
## Data Blocks ##
#################

data "external" "github_repo_commit" {
  program = ["git", "log", "-1", "--pretty={%x22output%x22:%x22%H%x22}"]
}

data "aws_ssm_parameter" "latest_deployed_github_repo_commit" {
  name = "latest_deployed_github_repo_commit"
}

resource "aws_ssm_parameter" "latest_deployed_github_repo_commit" {
  name  = "latest_deployed_github_repo_commit"
  type  = "String"
  value = data.external.github_repo_commit.result.output

  depends_on = [aws_instance.viz_pipeline]
}

data "cloudinit_config" "pipeline_setup" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/x-shellscript"
    filename     = "prc_setup.ps1"
    content = templatefile("${path.module}/templates/prc_setup.ps1.tftpl", {
      VIZ_DATA_HASH          = filemd5(data.archive_file.viz_pipeline_zip.output_path) # This causes the Viz EC2 to update when that folder changes
      Fileshare_IP           = "\\\\${aws_route53_record.viz_fileshare.name}"
      EGIS_HOST              = local.egis_host
      VIZ_ENVIRONMENT        = var.environment
      GITHUB_SSH_KEY_CONTENT = file("${path.root}/sensitive/vpp/viz/github")
      LICENSE_REG_CONTENT = templatefile("${path.module}/templates/pro_license.reg.tftpl", {
        LICENSE_SERVER = var.license_server_host
        PIPELINE_USER  = jsondecode(var.pipeline_user_secret_string)["username"]
      })
      FILEBEAT_YML_CONTENT               = templatefile("${path.module}/templates/filebeat.yml.tftpl", {})
      NWM_DATA_BUCKET                    = var.nwm_data_bucket
      FIM_DATA_BUCKET                    = var.fim_data_bucket
      FIM_OUTPUT_BUCKET                  = var.fim_output_bucket
      PYTHON_PREPROCESSING_BUCKET        = var.python_preprocessing_bucket
      RNR_DATA_BUCKET                    = var.rnr_data_bucket
      DEPLOYMENT_DATA_BUCKET             = var.deployment_data_bucket
      DEPLOYMENT_DATA_OBJECT             = aws_s3_object.setup_upload.key
      WINDOWS_SERVICE_STATUS             = var.windows_service_status
      WINDOWS_SERVICE_STARTUP            = var.windows_service_startup
      PIPELINE_USER                      = jsondecode(var.pipeline_user_secret_string)["username"]
      PIPELINE_USER_ACCOUNT_PASSWORD     = jsondecode(var.pipeline_user_secret_string)["password"]
      HYDROVIS_EGIS_PASS                 = var.hydrovis_egis_pass
      GITHUB_REPO_PREFIX                 = var.github_repo_prefix
      GITHUB_HOST                        = var.github_host
      LATEST_DEPLOYED_GITHUB_REPO_COMMIT = nonsensitive(data.aws_ssm_parameter.latest_deployed_github_repo_commit.value)
      VIZ_DB_HOST                        = var.viz_db_host
      VIZ_DB_DATABASE                    = var.viz_db_name
      VIZ_DB_USERNAME                    = jsondecode(var.viz_db_user_secret_string)["username"]
      VIZ_DB_PASSWORD                    = jsondecode(var.viz_db_user_secret_string)["password"]
      EGIS_DB_HOST                       = var.egis_db_host
      EGIS_DB_DATABASE                   = var.egis_db_name
      EGIS_DB_USERNAME                   = jsondecode(var.egis_db_secret_string)["username"]
      EGIS_DB_PASSWORD                   = jsondecode(var.egis_db_secret_string)["password"]
      AWS_REGION                         = var.region
      NWM_DATAFLOW_VERSION               = var.nwm_dataflow_version
    })
  }
}

##################
## VIZ PIPELINE ##
##################

data "archive_file" "viz_pipeline_zip" {
  type = "zip"

  source_dir = "${path.module}/../../../Source/Visualizations"

  output_path = "${path.module}/temp/viz_pipeline_${var.environment}_${var.region}.zip"
}

resource "aws_instance" "viz_pipeline" {
  ami                    = data.aws_ami.windows.id
  iam_instance_profile   = var.ec2_instance_profile_name
  instance_type          = "m5.xlarge"
  availability_zone      = var.ec2_instance_availability_zone
  vpc_security_group_ids = var.ec2_instance_sgs
  subnet_id              = var.ec2_instance_subnet
  key_name               = "hv-${var.environment}-ec2-key-pair-${var.region}"

  lifecycle {
    ignore_changes = [ami, tags]
  }

  tags = {
    "Name" = "hv-vpp-${var.environment}-viz-pipeline"
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
      "Name" = "hv-vpp-${var.environment}-viz-prc-drive"
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
    content = templatefile("${path.module}/templates/fs_setup.ps1.tftpl", {
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
  key_name               = "hv-${var.environment}-ec2-key-pair-${var.region}"

  lifecycle {
    ignore_changes = [ami, tags]
  }

  tags = {
    "Name" = "hv-vpp-${var.environment}-viz-fileshare"
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
      "Name" = "hv-vpp-${var.environment}-viz-fs-drive"
    }
  }

  user_data = data.cloudinit_config.fileshare_setup.rendered
  user_data_replace_on_change = true
}

resource "aws_route53_record" "viz_fileshare" {
  zone_id = var.private_route_53_zone.zone_id
  name    = "viz-fileshare.${var.private_route_53_zone.name}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.viz_fileshare.private_ip]
}
