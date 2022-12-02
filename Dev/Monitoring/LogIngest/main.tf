variable "environment" {
  type = string
}

variable "account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "ami_owner_account_id" {
  type = string
}

variable "logstash_instance_subnet_id" {
  type = string
}

variable "logstash_instance_availability_zone" {
  type = string
}

variable "logstash_instance_profile_name" {
  type = string
}

variable "logstash_instance_sgs" {
  type = list(string)
}

variable "deployment_bucket" {
  type = string
}

variable "saved_objects_s3_key" {
  type = string
}

variable "opensearch_domain_endpoint" {
  type = string
}

variable "dashboard_users_credentials_secret_strings" {
  type = list(string)
}

variable "dashboard_users_and_roles" {
  type = map(list(string))
}

variable "master_user_credentials_secret_string" {
  type = string
}

variable "es_sgs" {
  type = list(string)
}

variable "data_subnet_ids" {
  type = list(string)
}

variable "lambda_trigger_functions" {
  type = set(string)
}

variable "opensearch_domain_arn" {
  type = string
}


# Creates Logstash EC2 instance, where all other EC2 instances send their logs to and are routed to OpenSearch.
# Also imports saved objects into OpenSearch domain.
module "ec2" {
  source                 = "./EC2"

  environment            = var.environment
  ami_owner_account_id   = var.ami_owner_account_id
  region                 = var.region

  instance_availability_zone = var.logstash_instance_availability_zone
  instance_profile_name      = var.logstash_instance_profile_name
  instance_subnet_id         = var.logstash_instance_subnet_id
  instance_sgs               = var.logstash_instance_sgs

  deployment_bucket                          = var.deployment_bucket
  saved_objects_s3_key                       = var.saved_objects_s3_key
  opensearch_domain_endpoint                 = var.opensearch_domain_endpoint
  dashboard_users_credentials_secret_strings = var.dashboard_users_credentials_secret_strings
  dashboard_users_and_roles                  = var.dashboard_users_and_roles
  master_user_credentials_secret_string      = var.master_user_credentials_secret_string
}

# Creates Lambda Function that reads CloudWatch logs from other Lambdas and sends them to OpenSearch.
module "lambda" {
  source                 = "./Lambda"

  environment            = var.environment
  account_id             = var.account_id
  region                 = var.region

  data_subnet_ids            = var.data_subnet_ids
  es_sgs                     = var.es_sgs
  lambda_trigger_functions   = var.lambda_trigger_functions
  opensearch_domain_arn      = var.opensearch_domain_arn
  opensearch_domain_endpoint = var.opensearch_domain_endpoint
}

# Creates Lambda Function that reads CloudWatch logs from replicated S3 Buckets and sends them to OpenSearch.
module "s3" {
  source                 = "./S3"

  environment            = var.environment
  account_id             = var.account_id
  region                 = var.region

  data_subnet_ids            = var.data_subnet_ids
  es_sgs                     = var.es_sgs
  opensearch_domain_endpoint = var.opensearch_domain_endpoint
  lambda_role_arn            = module.lambda.role_arn

  buckets_and_parameters = {
    "hml" = {
      bucket_name         = "hydrovis-${var.environment}-hml-${var.region}"
      comparison_operator = "LessThanLowerThreshold"
    }
    "nwm" = {
      bucket_name         = "hydrovis-${var.environment}-nwm-${var.region}"
      comparison_operator = "LessThanLowerThreshold"
    }
    "pcpanl" = {
      bucket_name         = "hydrovis-${var.environment}-pcpanl-${var.region}"
      comparison_operator = "LessThanLowerThreshold"
    }
  }
}