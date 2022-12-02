variable "environment" {
  type = string
}

variable "account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "es_sgs" {
  type = list(string)
}

variable "data_subnet_ids" {
  type = list(string)
}

variable "dashboard_users_and_roles" {
  type = map(list(string))
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

variable "lambda_trigger_functions" {
  type = set(string)
}


# Creates OpenSearch Dashboards User Credentials and stores them in Secrets Manager.
module "dashboard_users_credentials" {
  source      = "./DashboardUsersCredentials"

  for_each    = merge(var.dashboard_users_and_roles, {monitoring_admin = [""]})
  environment = var.environment
  username    = each.key
}

# Creates OpenSearch Domain and S3 Object of Saved Objects.
module "opensearch" {
  source      = "./OpenSearch"

  environment  = var.environment
  account_id   = var.account_id
  region       = var.region

  deployment_bucket = var.deployment_bucket

  es_sgs                                = var.es_sgs
  data_subnet_ids                       = var.data_subnet_ids
  master_user_credentials_secret_string = module.dashboard_users_credentials["monitoring_admin"].secret_string
}

# Creates various methods of sending logs to OpenSearch to be indexed.
module "logingest" {
  source                 = "./LogIngest"

  # General Variables
  environment  = var.environment
  account_id   = var.account_id
  region       = var.region

  # EC2 Module
  ami_owner_account_id                       = var.ami_owner_account_id
  logstash_instance_availability_zone        = var.logstash_instance_availability_zone
  logstash_instance_profile_name             = var.logstash_instance_profile_name
  logstash_instance_subnet_id                = var.logstash_instance_subnet_id
  logstash_instance_sgs                      = var.logstash_instance_sgs
  deployment_bucket                          = var.deployment_bucket
  saved_objects_s3_key                       = module.opensearch.saved_objects_s3_key
  opensearch_domain_endpoint                 = module.opensearch.domain_endpoint
  dashboard_users_credentials_secret_strings = [ for name in keys(var.dashboard_users_and_roles) : module.dashboard_users_credentials[name].secret_string ]
  dashboard_users_and_roles                  = var.dashboard_users_and_roles
  master_user_credentials_secret_string      = module.dashboard_users_credentials["monitoring_admin"].secret_string

  # Lambda Module
  lambda_trigger_functions = var.lambda_trigger_functions
  opensearch_domain_arn    = module.opensearch.domain_arn
  es_sgs                   = var.es_sgs
  data_subnet_ids          = var.data_subnet_ids
}