variable "environment" {
  description = "Hydrovis environment"
  type        = string
}

variable "iam_role" {
  description = "iam profile name"
  type        = string
}

variable "subnet" {
  description = "VPC subnet"
  type        = string
}

variable "security_groups" {
  description = "VPC security groups"
  type        = list(string)
}

variable "kms_key_id" {
  description = "KMS Key for encryption"
  type        = string
}

resource "aws_sagemaker_notebook_instance" "ni" {
  name                   = "hv-vpp-${var.environment}-viz-notebook"
  role_arn               = var.iam_role
  instance_type          = "ml.t2.xlarge"
  volume_size            = 100
  subnet_id              = var.subnet
  security_groups        = var.security_groups
  kms_key_id             = var.kms_key_id
  # direct_internet_access = "Disabled"
  # root_access            = "Disabled"
}