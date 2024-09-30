variable "rise_s3_bucket" {
  description = "S3 Bucket that houses the rise input and output data"
  type        = string
}

variable "region" {
  description = "The AWS region where resources will be deployed"
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "The ID of the VPC where the instance will be deployed"
  type        = string
}

variable "subnet_id" {
  description = "The ID of the subnet where the instance will be deployed"
  type        = string
}

variable "env" {
  description = "Environment: used for naming / tagging resources"
  type        = string
  default     = "dev"
}

variable "instance_type" {
  description = "The type of the EC2 instance"
  type        = string
  default     = "c5a.8xlarge"
}

variable "ebs_volume_size" {
  description = "The size of the EBS volume in GB"
  type        = number
  default     = 20
}

variable "extra_policy_arn" {
  type    = string
  default = ""
  description = "Optional extra IAM policy to attach to the created role"
}

variable "git_repo_url" {
  description = "The Git repository URL for Replace and Route to clone."
  type        = string
  default     = "https://github.com/taddyb33/rise.git"
}

variable "git_branch" {
  description = "The branch of the Git repository to clone."
  type        = string
  default     = "main"
}

variable "rocky_linux_ami_id" {
  description = "Valid Rocky Linus 9 ID for your deploy target"
  type        = string
}
