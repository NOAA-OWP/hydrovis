#a prefix to give the ami
variable "ami_name_prefix" {
  type = string
}

#tags variable to add to ami
variable "tags" {
  type = map(any)
}

#the base ami to use
variable "base_ami" {
  type = string
}

#the arcgis enterprise version to build
variable "arcgisenterprise_version" {
  type = string
}

variable "imageBuilderLogBucket" {
  type = string
}

variable "deploymentS3Source" {
  type = string
}

variable "arcgisenterpriseConfig" {
  type = string
}

variable "arcgisServerConfig" {
  type = string
}

variable "WorkingFolder" {
  type = string
}

variable "image_version" {
  type = string
}

#destination regions where to copy completed ami
variable "destination_aws_regions" {
  type = list(string)
}

#destination accounts where to copy completed amis
variable "destination_aws_accounts" {
  type = list(string)
}

variable "img_securitygroup" {
  type = string
}

variable "img_subnet" {
  type = string
}

variable "aws_key_pair_name" {
  type = string
}

# the role to build the ami
variable "aws_role" {
  type = string

  validation {
    condition     = length(var.aws_role) > 4 && substr(var.aws_role, 0, 4) == "svc-"
    error_message = "The aws_role value must be a valid IAM role name, starting with \"svc-\"."
  }
}

# ssm parameters to update for the generated images
variable "aws_ssm_egis_amiid_store" {
  type = string
}

# number of days to retain the log events in the specified log group
variable "lambda_cloud_watch_log_group_retention_in_days" {
  description = "The number of days to retain the log events in the specified log group."
  type        = string
}
