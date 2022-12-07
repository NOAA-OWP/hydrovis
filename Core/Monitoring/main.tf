variable "environment" {
  type = string
}

variable "account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "opensearch_security_group_ids" {
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

variable "logstash_instance_security_group_ids" {
  type = list(string)
}

variable "deployment_bucket" {
  type = string
}

variable "lambda_trigger_functions" {
  type = set(string)
}

variable "buckets_and_parameters" {
  type = map(map(string))
}

variable "internal_route_53_zone" {
  type = object({
    name     = string
    zone_id  = string
  })
}

variable "vpc_id" {
  type = string
}

variable "task_role_arn" {
  type = string
}

variable "execution_role_arn" {
  type = string
}


# Creates OpenSearch Dashboards User Credentials and stores them in Secrets Manager.
module "dashboard-users-credentials" {
  source = "./DashboardUsersCredentials"

  for_each    = merge(var.dashboard_users_and_roles, {monitoring_admin = [""]})
  environment = var.environment
  username    = each.key
}

# Creates OpenSearch Domain, S3 Object of OpenSearch Saved Objects, and nginx proxy to forward traffic to OpenSearch.
module "opensearch" {
  source = "./OpenSearch"

  environment  = var.environment
  account_id   = var.account_id
  region       = var.region

  deployment_bucket = var.deployment_bucket

  opensearch_security_group_ids         = var.opensearch_security_group_ids
  data_subnet_ids                       = var.data_subnet_ids
  master_user_credentials_secret_string = module.dashboard-users-credentials["monitoring_admin"].secret_string

  # NginxProxy Module
  vpc_id             = var.vpc_id
  task_role_arn      = var.task_role_arn
  execution_role_arn = var.execution_role_arn
}

# Creates various methods of sending logs to OpenSearch to be indexed.
module "logingest" {
  source = "./LogIngest"

  # General Variables
  environment  = var.environment
  account_id   = var.account_id
  region       = var.region

  # EC2 Module
  ami_owner_account_id                       = var.ami_owner_account_id
  logstash_instance_availability_zone        = var.logstash_instance_availability_zone
  logstash_instance_profile_name             = var.logstash_instance_profile_name
  logstash_instance_subnet_id                = var.logstash_instance_subnet_id
  logstash_instance_security_group_ids       = var.logstash_instance_security_group_ids
  deployment_bucket                          = var.deployment_bucket
  saved_objects_s3_key                       = module.opensearch.saved_objects_s3_key
  opensearch_domain_endpoint                 = module.opensearch.domain_endpoint
  dashboard_users_credentials_secret_strings = [ for name in keys(var.dashboard_users_and_roles) : module.dashboard-users-credentials[name].secret_string ]
  dashboard_users_and_roles                  = var.dashboard_users_and_roles
  master_user_credentials_secret_string      = module.dashboard-users-credentials["monitoring_admin"].secret_string
  internal_route_53_zone                     = var.internal_route_53_zone

  # Lambda Module
  lambda_trigger_functions            = var.lambda_trigger_functions
  opensearch_domain_arn               = module.opensearch.domain_arn
  opensearch_security_group_ids       = var.opensearch_security_group_ids
  data_subnet_ids                     = var.data_subnet_ids

  # S3 Module
  buckets_and_parameters = var.buckets_and_parameters
}