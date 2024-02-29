variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "artifact_bucket_name" {
  type = string
}

variable "builder_role_instance_profile_name" {
  type = string
}

variable "builder_sg_id" {
  type = string
}

variable "builder_subnet_id" {
  type = string
}

variable "ami_sharing_account_ids" {
  type = list(string)
}

variable "egis_service_account_password" {
  type = string
}


module "linux" {
  source   = "./linux"

  environment = var.environment
  region      = var.region

  artifact_bucket_name               = var.artifact_bucket_name
  builder_role_instance_profile_name = var.builder_role_instance_profile_name
  builder_sg_id                      = var.builder_sg_id
  builder_subnet_id                  = var.builder_subnet_id
  ami_sharing_account_ids            = var.ami_sharing_account_ids
}

module "windows" {
  source   = "./windows"

  environment = var.environment
  region      = var.region

  artifact_bucket_name               = var.artifact_bucket_name
  builder_role_instance_profile_name = var.builder_role_instance_profile_name
  builder_sg_id                      = var.builder_sg_id
  builder_subnet_id                  = var.builder_subnet_id
  ami_sharing_account_ids            = var.ami_sharing_account_ids

  egis_service_account_password = var.egis_service_account_password
}

module "egis-servers" {
  source   = "./egis-servers"

  environment = var.environment
  region      = var.region

  artifact_bucket_name               = var.artifact_bucket_name
  builder_role_instance_profile_name = var.builder_role_instance_profile_name
  builder_sg_id                      = var.builder_sg_id
  builder_subnet_id                  = var.builder_subnet_id
  ami_sharing_account_ids            = var.ami_sharing_account_ids

  egis_service_account_password = var.egis_service_account_password
}
