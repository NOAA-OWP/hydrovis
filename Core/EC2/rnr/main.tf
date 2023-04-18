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
  type        = string
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

variable "nomads_url" {
  type = string
}

variable "s3_url" {
  type = string
}

variable "rnr_versions" {
  type = map(string)
}

variable "iam_role_arn" {
  description = "Role to use to reboot the ec2 instance."
  type        = string
}

locals {
  cloudinit_config_data = {
    write_files = [
      {
        path        = "/deploy_files/conus.ini"
        permissions = "0400"
        owner       = "ec2-user:ec2-user"
        content     = templatefile("${path.module}/templates/conus.ini.tftpl", {
          WRDS_HOST = "http://${var.dataservices_ip}"
          S3_URL = var.s3_url
          NOMADS_URL = var.nomads_url
        })
      },
      {
        path        = "/deploy_files/.env.devel"
        permissions = "0400"
        owner       = "ec2-user:ec2-user"
        content     = templatefile("${path.module}/templates/.env.devel.tftpl", {
          OUTPUT_BUCKET = var.output_bucket
        })
      }
    ]
  }
}

###############
## ARTIFACTS ##
###############

resource "aws_s3_object" "owp_viz_replace_route" {
  bucket = var.deployment_data_bucket
  key    = "rnr/owp-viz-replace-route.tgz"
  source = "${path.module}/owp-viz-replace-route.tgz"
  source_hash = filemd5("${path.module}/owp-viz-replace-route.tgz")
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

  depends_on = [
    aws_s3_object.owp_viz_replace_route,
    data.aws_s3_object.wrf_hydro,
    data.aws_s3_object.rnr_static
  ]

  user_data                   = data.cloudinit_config.startup.rendered
  user_data_replace_on_change = true
}


#################
## DATA BLOCKS ##
#################

data "aws_s3_object" "wrf_hydro" {
  bucket = var.deployment_data_bucket
  key    = "rnr/wrf_hydro.tgz"
}

data "aws_s3_object" "rnr_static" {
  bucket = var.deployment_data_bucket
  key    = "rnr/rnr_static.tgz"
}

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
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/x-shellscript"
    filename     = "install.sh"
    content      = templatefile("${path.module}/templates/install.sh.tftpl", {
      DEPLOYMENT_DATA_BUCKET = var.deployment_data_bucket
      netcdf_c_commit        = var.rnr_versions["netcdf_c_commit"]
      netcdf_fortran_commit  = var.rnr_versions["netcdf_fortran_commit"]
    })
  }

  part {
    content_type = "text/cloud-config"
    filename     = "cloud-config.yaml"
    content = <<-END
      #cloud-config
      ${jsonencode(local.cloudinit_config_data)}
    END
  }
}

resource "aws_sfn_state_machine" "reboot_replace_route_ec2_step_function" {
  name     = "reboot_replace_route_ec2_${var.environment}"
  role_arn = var.iam_role_arn

  definition = <<EOF
{
  "Comment": "A description of my state machine",
  "StartAt": "Reboot Replace and Route EC2",
  "States": {
    "Reboot Replace and Route EC2": {
      "Type": "Task",
      "End": true,
      "Parameters": {
        "InstanceIds": [
          "${aws_instance.replace_and_route.id}"
        ]
      },
      "Resource": "arn:aws:states:::aws-sdk:ec2:rebootInstances"
    }
  }
}
EOF
}

resource "aws_cloudwatch_event_rule" "daily_at_2330" {
  name                = "daily_at_2330"
  description         = "Fires every day at 23:30"
  schedule_expression = "cron(30 23 * * ? *)"
}

resource "aws_cloudwatch_event_target" "trigger_reboot_rnr_ec2" {
  rule      = aws_cloudwatch_event_rule.daily_at_2330.name
  arn       = aws_sfn_state_machine.reboot_replace_route_ec2_step_function.arn
  role_arn  = var.iam_role_arn
}
