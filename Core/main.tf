terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.24"
    }
  }
  backend "s3" {
    bucket                  = "hydrovis-terraform-state-us-east-1"
    key                     = "state"
    region                  = "us-east-1"
    profile                 = "prod"
    shared_credentials_file = "/cloud/aws/credentials"
  }
}

# See ./sensitive/envs/env.ENV.yaml for list of available variables
locals {
  env = yamldecode(file("./sensitive/envs/env.${terraform.workspace}.yaml"))
}

provider "aws" {
  region                  = local.env.region
  profile                 = local.env.environment
  shared_credentials_files = ["/cloud/aws/credentials"]

  default_tags {
    tags = merge(local.env.tags, {
      CreatedBy            = "Terraform"
    })
  }
}

###################### STAGE 1 ######################

# IAM Roles
module "iam-roles" {
  source = "./IAM/Roles"

  environment = local.env.environment
  account_id  = local.env.account_id
  region      = local.env.region
}

# IAM Users
module "iam-users" {
  source = "./IAM/Users"

  environment = local.env.environment
  account_id  = local.env.account_id
  region      = local.env.region
}

# KMS
module "kms" {
  source = "./KMS"

  environment     = local.env.environment
  account_id      = local.env.account_id
  region          = local.env.region
  admin_team_arns = local.env.admin_team_arns

  keys_and_key_users = {
    "encrypt-ec2" = [
      module.iam-roles.role_autoscaling.arn,
      module.iam-roles.role_HydrovisESRISSMDeploy.arn
    ]
    "egis" = [
      module.iam-roles.role_autoscaling.arn,
      module.iam-roles.role_HydrovisESRISSMDeploy.arn
    ]
    "rds-ingest" = [
      module.iam-roles.role_autoscaling.arn,
      module.iam-roles.role_hydrovis-hml-ingest-role.arn
    ]
    "rds-viz" = [
      module.iam-roles.role_autoscaling.arn,
      module.iam-roles.role_HydrovisESRISSMDeploy.arn
    ]
  }
}

# Secrets Manager Secrets
module "secrets-manager" {
  source = "./SecretsManager"

  environment = local.env.environment

  names_and_users = {
    "data-services-forecast-pg-rdssecret" = { "username" : "rfc_fcst_ro_user" }
    "data-services-location-pg-rdssecret" = { "username" : "location_ro_user" }
    "viz-processing-pg-rdssecret"         = { "username" : "postgres" }
    "viz_proc_admin_rw_user"              = { "username" : "viz_proc_admin_rw_user" }
    "viz_proc_dev_rw_user"                = { "username" : "viz_proc_dev_rw_user" }
    "ingest-pg-rdssecret"                 = { "username" : "postgres" }
    "ingest-mqsecret"                     = { "username" : "rabbit_admin" }
    "rds-rfc_fcst"                        = { "username" : "rfc_fcst" }
    "rds-rfc_fcst_user"                   = { "username" : "rfc_fcst_user" }
    "rds-nwm_viz_ro"                      = { "username" : "nwm_viz_ro" }
    "mq-aws-monitoring"                   = { "username" : "monitoring-AWS-OWNED-DO-NOT-DELETE" }
    "egis-pg-rds-secret"                  = { "username" : "hydrovis", "password" : local.env.egis-pg-rds_password }
    "egis-service-account"                = { "username" : "arcgis", "password" : local.env.egis-service-account_password }
  }
}

# S3 Buckets
module "s3" {
  source = "./S3"

  environment     = local.env.environment
  account_id      = local.env.account_id
  region          = local.env.region
  admin_team_arns = local.env.admin_team_arns

  buckets_and_bucket_users = {
    "deployment" = [
      module.iam-roles.role_HydrovisESRISSMDeploy.arn,
      module.iam-roles.role_HydrovisSSMInstanceProfileRole.arn,
      module.iam-roles.role_hydrovis-viz-proc-pipeline-lambda.arn,
      module.iam-roles.role_hydrovis-hml-ingest-role.arn,
      module.iam-roles.role_Hydroviz-RnR-EC2-Profile.arn,
      module.iam-users.user_WRDSServiceAccount.arn,
      module.iam-users.user_FIMServiceAccount.arn,
      module.iam-roles.role_hydrovis-ecs-resource-access.arn,
      module.iam-roles.role_hydrovis-ecs-task-execution.arn,
      module.iam-roles.role_hydrovis-sync-wrds-location-db.arn
    ]
    "fim" = [
      module.iam-roles.role_HydrovisESRISSMDeploy.arn,
      module.iam-roles.role_hydrovis-viz-proc-pipeline-lambda.arn,
      module.iam-roles.role_hydrovis-rds-s3-export.arn,
      module.iam-users.user_FIMServiceAccount.arn
    ]
    "hml-backup" = [
      module.iam-roles.role_hydrovis-hml-ingest-role.arn
    ]
    "rnr" = [
      module.iam-roles.role_hydrovis-viz-proc-pipeline-lambda.arn,
      module.iam-roles.role_Hydroviz-RnR-EC2-Profile.arn
    ]
    "session-manager-logs" = [
      module.iam-roles.role_HydrovisESRISSMDeploy.arn,
      module.iam-roles.role_HydrovisSSMInstanceProfileRole.arn,
      module.iam-roles.role_hydrovis-viz-proc-pipeline-lambda.arn,
      module.iam-roles.role_hydrovis-hml-ingest-role.arn,
      module.iam-roles.role_Hydroviz-RnR-EC2-Profile.arn
    ]
    "ised" = [
      module.iam-users.user_ISEDServiceAccount.arn
    ]
  }
}

module "egis" {
  source = "./eGIS"

  environment     = local.env.environment
  account_id      = local.env.account_id
  region          = local.env.region
  admin_team_arns = local.env.admin_team_arns

  role_HydrovisESRISSMDeploy_arn = module.iam-roles.role_HydrovisESRISSMDeploy.arn
  role_autoscaling_arn           = module.iam-roles.role_autoscaling.arn
}

# S3 Replication
module "s3-replication" {
  source = "./S3Replication"

  environment                                = local.env.environment
  account_id                                 = local.env.account_id
  prod_account_id                            = local.env.prod_account_id
  uat_account_id                             = local.env.uat_account_id
  ti_account_id                              = local.env.ti_account_id
  region                                     = local.env.region
  admin_team_arns                            = local.env.admin_team_arns
  user_data-ingest-service-user_arn          = module.iam-roles.role_hydrovis-hml-ingest-role.arn
  role_hydrovis-viz-proc-pipeline-lambda_arn = module.iam-roles.role_hydrovis-viz-proc-pipeline-lambda.arn
  role_Hydroviz-RnR-EC2-Profile_arn          = module.iam-roles.role_Hydroviz-RnR-EC2-Profile.arn
}

###################### STAGE 2 ######################

# VPC, Subnets, VGW
module "vpc" {
  source = "./VPC"

  environment                        = local.env.environment
  region                             = local.env.region
  vpc_ip_block                       = local.env.vpc_ip_block
  nwave_ip_block                     = local.env.nwave_ip_block
  public_route_peering_ip_block      = local.env.public_route_peering_ip_block
  public_route_peering_connection_id = local.env.public_route_peering_connection_id
}

# Route53 DNS
module "route53" {
  source = "./Route53"

  vpc_main_id = module.vpc.vpc_main.id
}

# SGs
module "security-groups" {
  source = "./SecurityGroups"

  environment                              = local.env.environment
  nwave_ip_block                           = local.env.nwave_ip_block
  vpc_ip_block                             = local.env.vpc_ip_block
  nwc_ip_block                             = local.env.nwc_ip_block
  vpc_main_id                              = module.vpc.vpc_main.id
  vpc_main_cidr_block                      = module.vpc.vpc_main.cidr_block
  subnet_hydrovis-sn-prv-data1a_cidr_block = module.vpc.subnet_hydrovis-sn-prv-data1a.cidr_block
  subnet_hydrovis-sn-prv-data1b_cidr_block = module.vpc.subnet_hydrovis-sn-prv-data1b.cidr_block
  public_route_peering_ip_block            = local.env.public_route_peering_ip_block
}

# VPCe's
module "vpces" {
  source = "./VPC/VPCe"

  environment                      = local.env.environment
  region                           = local.env.region
  vpc_main_id                      = module.vpc.vpc_main.id
  subnet_hydrovis-sn-prv-data1b_id = module.vpc.subnet_hydrovis-sn-prv-data1b.id
  route_table_private_id           = module.vpc.route_table_private.id
  ssm-session-manager-sg_id        = module.security-groups.ssm-session-manager-sg.id
  opensearch-access_id             = module.security-groups.opensearch-access.id
}

###################### STAGE 3 ######################

# Simple Service Notifications
module "sns" {
  source = "./SNS"

  environment               = local.env.environment
  nwm_data_bucket           = module.s3-replication.buckets["nwm"].bucket
  nwm_max_flows_data_bucket = module.s3.buckets["fim"].bucket
  rnr_max_flows_data_bucket = module.s3.buckets["rnr"].bucket
  error_email_list          = local.env.sns_email_lists
}

# RDS
module "rds-ingest" {
  source = "./RDS/ingest"

  environment               = local.env.environment
  subnet-data1a             = module.vpc.subnet_hydrovis-sn-prv-data1a.id
  subnet-data1b             = module.vpc.subnet_hydrovis-sn-prv-data1b.id
  db_ingest_secret_string   = module.secrets-manager.secret_strings["ingest-pg-rdssecret"]
  rds_kms_key               = module.kms.key_arns["rds-ingest"]
  db_ingest_security_groups = [module.security-groups.hydrovis-RDS.id]
}

module "rds-viz" {
  source = "./RDS/viz"

  environment                       = local.env.environment
  subnet-app1a                      = module.vpc.subnet_hydrovis-sn-prv-app1a.id
  subnet-app1b                      = module.vpc.subnet_hydrovis-sn-prv-app1b.id
  db_viz_processing_secret_string   = module.secrets-manager.secret_strings["viz-processing-pg-rdssecret"]
  rds_kms_key                       = module.kms.key_arns["rds-viz"]
  db_viz_processing_security_groups = [module.security-groups.hydrovis-RDS.id]
  viz_db_name                       = local.env.viz_db_name
  role_hydrovis-rds-s3-export_arn   = module.iam-roles.role_hydrovis-rds-s3-export.arn
}

# Import EGIS DB
data "aws_db_instance" "egis_rds" {
  db_instance_identifier = local.env.environment == "prod" ? "hv-prd-egis-rds-pg-egdb" : local.env.environment == "uat" ? "hv-uat-egis-db-pg-egdb" : local.env.environment == "ti" ? "hv-ti-egis-rds-pg-egdb" : ""
}

# Lambda Layers
module "lambda_layers" {
  source = "./LAMBDA/layers"

  environment        = local.env.environment
  viz_environment    = local.env.environment == "prod" ? "production" : local.env.environment == "uat" ? "staging" : local.env.environment == "ti" ? "staging" : "development"
  deployment_bucket = module.s3.buckets["deployment"].bucket
}

# Lambda Functions
module "viz_lambda_functions" {
  source = "./LAMBDA/viz_functions"

  environment                   = local.env.environment
  account_id                    = local.env.account_id
  region                        = local.env.region
  viz_authoritative_bucket      = module.s3.buckets["deployment"].bucket
  nwm_data_bucket               = module.s3-replication.buckets["nwm"].bucket
  fim_data_bucket               = module.s3.buckets["deployment"].bucket
  fim_output_bucket             = module.s3.buckets["fim"].bucket
  max_flows_bucket              = module.s3.buckets["fim"].bucket
  deployment_bucket            = module.s3.buckets["deployment"].bucket
  viz_cache_bucket              = module.s3.buckets["fim"].bucket
  fim_version                   = local.env.fim_version
  lambda_role                   = module.iam-roles.role_hydrovis-viz-proc-pipeline-lambda.arn
  sns_topics                    = module.sns.sns_topics
  email_sns_topics              = module.sns.email_sns_topics
  es_logging_layer              = module.lambda_layers.es_logging.arn
  xarray_layer                  = module.lambda_layers.xarray.arn
  pandas_layer                  = module.lambda_layers.pandas.arn
  arcgis_python_api_layer       = module.lambda_layers.arcgis_python_api.arn
  psycopg2_sqlalchemy_layer     = module.lambda_layers.psycopg2_sqlalchemy.arn
  requests_layer                = module.lambda_layers.requests.arn
  viz_lambda_shared_funcs_layer = module.lambda_layers.viz_lambda_shared_funcs.arn
  db_lambda_security_groups     = [module.security-groups.hydrovis-RDS.id, module.security-groups.egis-overlord.id]
  nat_sg_group                  = module.security-groups.hydrovis-nat-sg.id
  db_lambda_subnets             = [module.vpc.subnet_hydrovis-sn-prv-data1a.id, module.vpc.subnet_hydrovis-sn-prv-data1b.id]
  viz_db_host                   = module.rds-viz.rds-viz-processing.address
  viz_db_name                   = local.env.viz_db_name
  viz_db_user_secret_string     = module.secrets-manager.secret_strings["viz_proc_admin_rw_user"]
  egis_db_host                  = data.aws_db_instance.egis_rds.address
  egis_db_name                  = local.env.egis_db_name
  egis_db_user_secret_string    = module.secrets-manager.secret_strings["egis-pg-rds-secret"]
  egis_portal_password          = local.env.viz_ec2_hydrovis_egis_pass
  dataservices_ip               = module.data-services.dataservices-ip
  viz_pipeline_step_function_arn = module.step_functions.viz_pipeline_step_function.arn
}

# Simple Service Notifications
module "step_functions" {
  source = "./StepFunctions"

  lambda_role = module.iam-roles.role_hydrovis-viz-proc-pipeline-lambda.arn
  environment = local.env.environment
  schism_fim_processing_arn = module.viz_lambda_functions
  optimize_rasters_arn = module.viz_lambda_functions.optimize_rasters.arn
  update_egis_data_arn = module.viz_lambda_functions.update_egis_data.arn
  fim_data_prep_arn = module.viz_lambda_functions.fim_data_prep.arn
  hand_fim_processing_arn = module.viz_lambda_functions
  db_postprocess_sql_arn = module.viz_lambda_functions.db_postprocess_sql.arn
  db_ingest_arn = module.viz_lambda_functions.db_ingest.arn
  raster_processing_arn = module.viz_lambda_functions.raster_processing.arn
  publish_service_arn = module.viz_lambda_functions.publish_service.arn
  email_sns_topics              = module.sns.email_sns_topics
}

# Simple Service Notifications
module "eventbridge" {
  source = "./EventBridge"

  scheduled_rules                = local.env.nwm_3_0_event_bridge_targets
}

# MQ
module "mq-ingest" {
  source = "./MQ/ingest"

  environment               = local.env.environment
  mq_ingest_subnets         = [module.vpc.subnet_hydrovis-sn-prv-data1a.id]
  mq_ingest_security_groups = [module.security-groups.hv-rabbitmq.id]
  mq_ingest_secret_string   = module.secrets-manager.secret_strings["ingest-mqsecret"]
}

module "rds-bastion" {
  source = "./EC2/RDSBastion"

  environment                    = local.env.environment
  ami_owner_account_id           = local.env.ami_owner_account_id
  ec2_instance_profile_name      = module.iam-roles.profile_hydrovis-hml-ingest-role.name
  ec2_instance_subnet            = module.vpc.subnet_hydrovis-sn-prv-data1a.id
  ec2_instance_availability_zone = module.vpc.subnet_hydrovis-sn-prv-data1a.availability_zone
  ec2_instance_sgs = [
    module.security-groups.hydrovis-RDS.id,
    module.security-groups.hv-rabbitmq.id,
    module.security-groups.ssm-session-manager-sg.id
  ]
  kms_key_arn            = module.kms.key_arns["encrypt-ec2"]
  data_deployment_bucket = module.s3.buckets["deployment"].bucket

  ingest_db_secret_string        = module.secrets-manager.secret_strings["ingest-pg-rdssecret"]
  ingest_db_address              = module.rds-ingest.rds-ingest.address
  ingest_db_port                 = module.rds-ingest.rds-ingest.port
  nwm_viz_ro_secret_string       = module.secrets-manager.secret_strings["rds-nwm_viz_ro"]
  rfc_fcst_secret_string         = module.secrets-manager.secret_strings["rds-rfc_fcst"]
  rfc_fcst_ro_user_secret_string = module.secrets-manager.secret_strings["data-services-forecast-pg-rdssecret"]
  rfc_fcst_user_secret_string    = module.secrets-manager.secret_strings["rds-rfc_fcst_user"]
  location_ro_user_secret_string = module.secrets-manager.secret_strings["data-services-location-pg-rdssecret"]
  location_db_name               = local.env.location_db_name
  forecast_db_name               = local.env.forecast_db_name

  ingest_mq_secret_string = module.secrets-manager.secret_strings["ingest-mqsecret"]
  ingest_mq_endpoint      = module.mq-ingest.mq-ingest.instances.0.endpoints.0

  viz_proc_admin_rw_secret_string = module.secrets-manager.secret_strings["viz_proc_admin_rw_user"]
  viz_proc_dev_rw_secret_string   = module.secrets-manager.secret_strings["viz_proc_dev_rw_user"]
  viz_db_secret_string            = module.secrets-manager.secret_strings["viz-processing-pg-rdssecret"]
  viz_db_address                  = module.rds-viz.rds-viz-processing.address
  viz_db_port                     = module.rds-viz.rds-viz-processing.port
  viz_db_name                     = local.env.viz_db_name
  egis_db_secret_string           = module.secrets-manager.secret_strings["egis-pg-rds-secret"]
  egis_db_address                 = data.aws_db_instance.egis_rds.address
  egis_db_port                    = data.aws_db_instance.egis_rds.port
  egis_db_name                    = local.env.egis_db_name
  fim_version                     = local.env.fim_version
}

module "ingest_lambda_functions" {
  source = "./LAMBDA/ingest_functions"

  environment                 = local.env.environment
  region                      = local.env.region
  deployment_bucket           = module.s3.buckets["deployment"].bucket
  lambda_role                 = module.iam-roles.role_hydrovis-hml-ingest-role.arn
  psycopg2_sqlalchemy_layer   = module.lambda_layers.psycopg2_sqlalchemy.arn
  pika_layer                  = module.lambda_layers.pika.arn
  rfc_fcst_user_secret_string = module.secrets-manager.secret_strings["rds-rfc_fcst_user"]
  mq_ingest_id                = module.mq-ingest.mq-ingest.id
  db_ingest_name              = local.env.forecast_db_name
  db_ingest_host              = module.rds-ingest.rds-ingest.address
  mq_ingest_port              = split(":", module.mq-ingest.mq-ingest.instances.0.endpoints.0)[2]
  db_ingest_port              = module.rds-ingest.rds-ingest.port
  primary_hml_bucket_name     = module.s3-replication.buckets["hml"].bucket
  primary_hml_bucket_arn      = module.s3-replication.buckets["hml"].arn
  backup_hml_bucket_name      = module.s3.buckets["hml-backup"].bucket
  backup_hml_bucket_arn       = module.s3.buckets["hml-backup"].arn
  lambda_subnet_ids           = [module.vpc.subnet_hydrovis-sn-prv-data1a.id, module.vpc.subnet_hydrovis-sn-prv-data1b.id]
  lambda_security_group_ids   = [module.security-groups.hydrovis-nat-sg.id]
}


# Monitoring Module
module "monitoring" {
  source = "./Monitoring"

  # General Variables
  environment                   = local.env.environment
  account_id                    = local.env.account_id
  region                        = local.env.region
  opensearch_security_group_ids = [module.security-groups.opensearch-access.id]
  data_subnet_ids               = [
    module.vpc.subnet_hydrovis-sn-prv-data1a.id,
    module.vpc.subnet_hydrovis-sn-prv-data1b.id
  ]

  # DashboardUsersCredentials Module
  dashboard_users_and_roles = {
    wpod = ["readall", "opensearch_dashboards_read_only"]
  }

  # OpenSearch Module
  vpc_id             = module.vpc.vpc_main.id
  task_role_arn      = module.iam-roles.role_hydrovis-ecs-resource-access.arn
  execution_role_arn = module.iam-roles.role_hydrovis-ecs-task-execution.arn

  # LogIngest Module
  ami_owner_account_id                 = local.env.ami_owner_account_id
  logstash_instance_subnet_id          = module.vpc.subnet_hydrovis-sn-prv-app1a.id
  logstash_instance_availability_zone  = module.vpc.subnet_hydrovis-sn-prv-app1a.availability_zone
  logstash_instance_profile_name       = module.iam-roles.profile_HydrovisSSMInstanceProfileRole.name
  logstash_instance_security_group_ids = [
    module.security-groups.opensearch-access.id,
    module.security-groups.ssm-session-manager-sg.id
  ]
  deployment_bucket                    = module.s3.buckets["deployment"].bucket
  lambda_trigger_functions             = [
    module.viz_lambda_functions.max_flows.function_name,
    module.ingest_lambda_functions.hml_reciever.function_name,
    module.viz_lambda_functions.db_ingest.function_name
  ]
  buckets_and_parameters = {
    "hml" = {
      bucket_name         = "hydrovis-${local.env.environment}-hml-${local.env.region}"
      comparison_operator = "LessThanLowerThreshold"
    }
    "nwm" = {
      bucket_name         = "hydrovis-${local.env.environment}-nwm-${local.env.region}"
      comparison_operator = "LessThanLowerThreshold"
    }
    "pcpanl" = {
      bucket_name         = "hydrovis-${local.env.environment}-pcpanl-${local.env.region}"
      comparison_operator = "LessThanLowerThreshold"
    }
  }
  internal_route_53_zone = {
    name    = module.route53.hydrovis_internal_zone.name
    zone_id = module.route53.hydrovis_internal_zone.zone_id
  }
}


# Data Ingest
module "data-ingest-ec2" {
  source = "./EC2/Ingest"

  environment            = local.env.environment
  ami_owner_account_id   = local.env.ami_owner_account_id
  prc1_subnet            = module.vpc.subnet_hydrovis-sn-prv-data1a.id
  prc2_subnet            = module.vpc.subnet_hydrovis-sn-prv-data1b.id
  prc1_availability_zone = module.vpc.subnet_hydrovis-sn-prv-data1a.availability_zone
  prc2_availability_zone = module.vpc.subnet_hydrovis-sn-prv-data1b.availability_zone
  ec2_instance_sgs = [
    module.security-groups.hydrovis-RDS.id,
    module.security-groups.hv-rabbitmq.id,
    module.security-groups.ssm-session-manager-sg.id
  ]
  ec2_kms_key               = module.kms.key_arns["encrypt-ec2"]
  ec2_instance_profile_name = module.iam-roles.profile_hydrovis-hml-ingest-role.name
  deployment_data_bucket    = module.s3.buckets["deployment"].bucket

  mq_ingest_endpoint      = module.mq-ingest.mq-ingest.instances.0.endpoints.0
  mq_ingest_secret_string = module.secrets-manager.secret_strings["rds-rfc_fcst_user"]
  db_host                 = module.rds-ingest.rds-ingest.address
  db_ingest_secret_string = module.secrets-manager.secret_strings["rds-rfc_fcst_user"]
}

#Data Services (WRDS APIs)
module "data-services" {
  source = "./EC2/DataServices"

  environment                    = local.env.environment
  ami_owner_account_id           = local.env.ami_owner_account_id
  ec2_instance_subnet            = module.vpc.subnet_hydrovis-sn-prv-data1a.id
  ec2_instance_availability_zone = module.vpc.subnet_hydrovis-sn-prv-data1a.availability_zone
  ec2_instance_sgs = [
    module.security-groups.hydrovis-RDS.id,
    module.security-groups.hydrovis-nat-sg.id,
    module.security-groups.ssm-session-manager-sg.id
  ]
  ec2_instance_profile_name          = module.iam-roles.profile_HydrovisSSMInstanceProfileRole.name
  kms_key_arn                        = module.kms.key_arns["encrypt-ec2"]
  rds_host                           = module.rds-ingest.rds-ingest.address
  location_db_name                   = local.env.location_db_name
  forecast_db_name                   = local.env.forecast_db_name
  location_credentials_secret_string = module.secrets-manager.secret_strings["data-services-location-pg-rdssecret"]
  forecast_credentials_secret_string = module.secrets-manager.secret_strings["data-services-forecast-pg-rdssecret"]
  vlab_repo_prefix                   = local.env.data_services_vlab_repo_prefix
  data_services_versions             = local.env.data_services_versions
}

module "rnr_ec2" {
  source = "./EC2/rnr"

  ami_owner_account_id           = local.env.ami_owner_account_id
  ec2_instance_subnet            = module.vpc.subnet_hydrovis-sn-prv-data1a.id
  ec2_instance_availability_zone = module.vpc.subnet_hydrovis-sn-prv-app1a.availability_zone
  ec2_instance_sgs               = [module.security-groups.ssm-session-manager-sg.id]
  environment                    = local.env.environment
  output_bucket                  = module.s3.buckets["rnr"].bucket
  deployment_data_bucket         = module.s3.buckets["deployment"].bucket
  ec2_kms_key                    = module.kms.key_arns["encrypt-ec2"]
  ec2_instance_profile_name      = module.iam-roles.profile_Hydroviz-RnR-EC2-Profile.name
  dataservices_ip                = module.data-services.dataservices-ip
  nomads_url                     = local.env.rnr_nomads_url
  s3_url                         = local.env.rnr_s3_url
  rnr_versions                   = local.env.rnr_versions
}

module "egis_license_manager" {
  source = "./EC2/LicenseManager"

  environment                    = local.env.environment
  ami_owner_account_id           = local.env.ami_owner_account_id
  region                         = local.env.region
  ec2_instance_subnet            = module.vpc.subnet_hydrovis-sn-prv-web1a.id
  ec2_instance_availability_zone = module.vpc.subnet_hydrovis-sn-prv-app1a.availability_zone
  ec2_instance_sgs = [
    module.security-groups.ssm-session-manager-sg.id,
    module.security-groups.egis-overlord.id
  ]
  ec2_instance_profile_name = module.iam-roles.profile_HydrovisESRISSMDeploy.name
  ec2_kms_key               = module.kms.key_arns["egis"]
}

module "egis_monitor" {
  source = "./EC2/ArcGIS_Monitor"

  environment          = local.env.environment
  ami_owner_account_id = local.env.ami_owner_account_id
  region               = local.env.region
  ec2_instance_subnet  = module.vpc.subnet_hydrovis-sn-prv-web1a.id
  ec2_instance_sgs = [
    module.security-groups.ssm-session-manager-sg.id,
    module.security-groups.egis-overlord.id
  ]
  ec2_instance_profile_name = module.iam-roles.profile_HydrovisESRISSMDeploy.name
  ec2_kms_key               = module.kms.key_arns["egis"]
}

###################### STAGE 4 ######################

module "viz_ec2" {
  source = "./EC2/viz"

  environment                    = local.env.environment
  ami_owner_account_id           = local.env.ami_owner_account_id
  region                         = local.env.region
  ec2_instance_subnet            = module.vpc.subnet_hydrovis-sn-prv-app1a.id
  ec2_instance_availability_zone = module.vpc.subnet_hydrovis-sn-prv-app1a.availability_zone
  ec2_instance_sgs = [
    module.security-groups.ssm-session-manager-sg.id,
    module.security-groups.egis-overlord.id
  ]
  dataservices_ip             = module.data-services.dataservices-ip
  fim_data_bucket             = module.s3.buckets["deployment"].bucket
  fim_output_bucket           = module.s3.buckets["fim"].bucket
  nwm_data_bucket             = module.s3-replication.buckets["nwm"].bucket
  nwm_max_flows_data_bucket   = module.s3.buckets["fim"].bucket
  rnr_max_flows_data_bucket   = module.s3.buckets["rnr"].bucket
  deployment_data_bucket      = module.s3.buckets["deployment"].bucket
  kms_key_arn                 = module.kms.key_arns["egis"]
  ec2_instance_profile_name   = module.iam-roles.profile_HydrovisESRISSMDeploy.name
  fim_version                 = local.env.fim_version
  windows_service_status      = local.env.viz_ec2_windows_service_status
  windows_service_startup     = local.env.viz_ec2_windows_service_startup
  license_server_ip           = module.egis_license_manager.license_manager_ip
  pipeline_user_secret_string = module.secrets-manager.secret_strings["egis-service-account"]
  hydrovis_egis_pass          = local.env.viz_ec2_hydrovis_egis_pass
  vlab_repo_prefix            = local.env.viz_ec2_vlab_repo_prefix
  vlab_host                   = local.env.viz_ec2_vlab_host
  github_repo_prefix          = local.env.viz_ec2_github_repo_prefix
  github_host                 = local.env.viz_ec2_github_host
  viz_db_host                 = module.rds-viz.rds-viz-processing.address
  viz_db_name                 = local.env.viz_db_name
  viz_db_user_secret_string   = module.secrets-manager.secret_strings["viz_proc_admin_rw_user"]
  egis_db_host                = data.aws_db_instance.egis_rds.address
  egis_db_name                = local.env.egis_db_name
  egis_db_secret_string       = module.secrets-manager.secret_strings["egis-pg-rds-secret"]
}

module "sagemaker" {
  source = "./Sagemaker"

  environment     = local.env.environment
  iam_role        = module.iam-roles.role_hydrovis-viz-proc-pipeline-lambda.arn
  subnet          = module.vpc.subnet_hydrovis-sn-prv-data1a.id
  security_groups = [module.security-groups.hydrovis-RDS.id, module.security-groups.egis-overlord.id]
  kms_key_id      = module.kms.key_arns["encrypt-ec2"]
}

module "sync_wrds_location_db" {
  source = "./SyncWrdsLocationDB"

  environment               = local.env.environment
  region                    = local.env.region
  iam_role_arn              = module.iam-roles.role_hydrovis-sync-wrds-location-db.arn
  email_sns_topics          = module.sns.email_sns_topics
  requests_lambda_layer     = module.lambda_layers.requests.arn
  rds_bastion_id            = module.rds-bastion.instance-id
  test_data_services_id     = module.data-services.dataservices-test-instance-id
  lambda_security_groups    = [module.security-groups.hydrovis-RDS.id]
  lambda_subnets            = [module.vpc.subnet_hydrovis-sn-prv-data1a.id, module.vpc.subnet_hydrovis-sn-prv-data1b.id]
  db_dumps_bucket           = module.s3.buckets["deployment"].bucket
}
