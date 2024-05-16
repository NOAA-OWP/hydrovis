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
  env = yamldecode(file("./sensitive/vpp/envs/${split("_", terraform.workspace)[1]}/env.${split("_", terraform.workspace)[0]}.yaml"))
}

provider "aws" {
  region                   = local.env.region
  profile                  = local.env.environment
  shared_credentials_files = ["/cloud/aws/credentials"]
  default_tags {
    tags = merge(local.env.tags, {
      CreatedBy = "Terraform"
    })
  }
}

provider "aws" {
  alias                    = "sns"
  region                   = local.env.nws_shared_account_sns_region
  profile                  = local.env.environment
  shared_credentials_files = ["/cloud/aws/credentials"]

  default_tags {
    tags = merge(local.env.tags, {
      CreatedBy = "Terraform"
    })
  }
}

###################### STAGE 1 ######################

# IAM Roles
module "iam-roles" {
  source = "./IAM/Roles"

  environment                  = local.env.environment
  account_id                   = local.env.account_id
  ti_account_id                = local.env.ti_account_id
  uat_account_id               = local.env.uat_account_id
  prod_account_id              = local.env.prod_account_id
  region                       = local.env.region
  nws_shared_account_s3_bucket = local.env.nws_shared_account_s3_bucket
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
      module.iam-roles.role_data_ingest.arn
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
    "viz-proc-admin-rw-user"              = { "username" : "viz_proc_admin_rw_user" }
    "viz-proc-dev-rw-user"                = { "username" : "viz_proc_dev_rw_user" }
    "ingest-pg-rdssecret"                 = { "username" : "postgres" }
    "ingest-mqsecret"                     = { "username" : "rabbit_admin" }
    "rds-rfc-fcst"                        = { "username" : "rfc_fcst" }
    "rds-rfc-fcst-user"                   = { "username" : "rfc_fcst_user" }
    "rds-nwm-viz-ro"                      = { "username" : "nwm_viz_ro" }
    "mq-aws-monitoring"                   = { "username" : "monitoring-AWS-OWNED-DO-NOT-DELETE" }
    "egis-service-account"                = { "username" : "arcgis", "password" : local.env.egis-service-account_password }
    "egis-master-pg-rds-secret"           = { "username" : "master", "password" : local.env.egis-master-pg-rds_password }
    "egis-pg-rds-secret"                  = { "username" : "hydrovis" }
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
      module.iam-roles.role_data_services.arn,
      module.iam-roles.role_viz_pipeline.arn,
      module.iam-roles.role_data_ingest.arn,
      module.iam-roles.role_rnr.arn,
      module.iam-users.user_WRDSServiceAccount.arn,
      module.iam-users.user_FIMServiceAccount.arn,
      module.iam-roles.role_sync_wrds_location_db.arn,
      "arn:aws:iam::${local.env.account_id}:role/hv-vpp-${local.env.environment}-${local.env.region}-schism-execution"
    ]
    "fim" = [
      module.iam-roles.role_HydrovisESRISSMDeploy.arn,
      module.iam-roles.role_viz_pipeline.arn,
      module.iam-roles.role_rds_s3_export.arn,
      module.iam-users.user_FIMServiceAccount.arn,
      "arn:aws:iam::${local.env.account_id}:role/hv-vpp-${local.env.environment}-${local.env.region}-schism-execution"
    ]
    "hml-backup" = [
      module.iam-roles.role_data_ingest.arn
    ]
    "rnr" = [
      module.iam-roles.role_viz_pipeline.arn,
      module.iam-roles.role_rnr.arn
    ]
    "session-manager-logs" = [
      module.iam-roles.role_HydrovisESRISSMDeploy.arn,
      module.iam-roles.role_data_services.arn,
      module.iam-roles.role_viz_pipeline.arn,
      module.iam-roles.role_data_ingest.arn,
      module.iam-roles.role_rnr.arn
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

  environment                              = local.env.environment
  account_id                               = local.env.account_id
  prod_account_id                          = local.env.prod_account_id
  uat_account_id                           = local.env.uat_account_id
  ti_account_id                            = local.env.ti_account_id
  region                                   = local.env.region
  admin_team_arns                          = local.env.admin_team_arns
  user_S3ReplicationDataServiceAccount_arn = module.iam-users.user_S3ReplicationDataServiceAccount.arn
  user_data-ingest-service-user_arn        = module.iam-roles.role_data_ingest.arn
  role_viz_pipeline_arn                    = module.iam-roles.role_viz_pipeline.arn
  role_rnr_arn                             = module.iam-roles.role_rnr.arn
}

# ###################### STAGE 2 ######################

# VPC, Subnets, VGW
module "vpc" {
  source = "./VPC"

  environment        = local.env.environment
  account_id         = local.env.account_id
  region             = local.env.region
  vpc_ip_block       = local.env.vpc_ip_block
  nwave_ip_block     = local.env.nwave_ip_block
  transit_gateway_id = local.env.transit_gateway_id
}

# Route53 DNS
module "private-route53" {
  source = "./Route53/private/hydrovis"

  vpc_main_id = module.vpc.vpc_main.id
}

# SGs
module "security-groups" {
  source = "./SecurityGroups"

  environment         = local.env.environment
  nwave_ip_block      = local.env.nwave_ip_block
  vpc_main_id         = module.vpc.vpc_main.id
  vpc_main_cidr_block = module.vpc.vpc_main.cidr_block
}

# VPCe's
module "vpces" {
  source = "./VPC/VPCe"

  environment              = local.env.environment
  region                   = local.env.region
  vpc_main_id              = module.vpc.vpc_main.id
  subnet_a_id              = module.vpc.subnet_private_a.id
  subnet_b_id              = module.vpc.subnet_private_b.id
  route_table_private_a_id = module.vpc.route_table_private_a.id
  route_table_private_b_id = module.vpc.route_table_private_b.id
  vpc_access_sg_id         = module.security-groups.vpc_access.id
}

# Image Builder Pipelines
module "image-builder" {
  source = "./ImageBuilder"

  # Only build the Image Builder Pipelines in the one specific environment, then the AMIs are shared to the other environments
  count = local.env.account_id == local.env.ami_owner_account_id ? 1 : 0

  environment                     = local.env.environment
  account_id                      = local.env.account_id
  region                          = local.env.region
  uat_account_id                  = local.env.uat_account_id
  prod_account_id                 = local.env.prod_account_id
  vpc_ip_block                    = local.env.vpc_ip_block
  vpc_main_id                     = module.vpc.vpc_main.id
  admin_team_arns                 = local.env.admin_team_arns
  session_manager_logs_bucket_arn = module.s3.buckets["session-manager-logs"].arn
  session_manager_logs_kms_arn    = module.s3.keys["session-manager-logs"].arn
  rnr_bucket_arn                  = module.s3.buckets["rnr"].arn
  rnr_kms_arn                     = module.s3.keys["rnr"].arn
  builder_subnet_id               = module.vpc.subnet_private_b.id
  egis_service_account_password   = local.env.egis-service-account_password
}

###################### STAGE 3 ######################

# Simple Service Notifications
module "sns" {
  source = "./SNS"

  environment      = local.env.environment
  region           = local.env.region
  rnr_data_bucket  = module.s3.buckets["rnr"].bucket
  error_email_list = local.env.sns_email_lists
}

module "sagemaker" {
  source = "./Sagemaker"

  environment = local.env.environment
  iam_role    = module.iam-roles.role_viz_pipeline.arn
  subnet      = module.vpc.subnet_private_a.id
  security_groups = [
    module.security-groups.rds.id,
    module.security-groups.egis_overlord.id
  ]
  kms_key_id = module.kms.key_arns["encrypt-ec2"]
}

# Lambda Layers
module "lambda-layers" {
  source = "./LAMBDA/layers"

  environment       = local.env.environment
  region            = local.env.region
  viz_environment   = local.env.environment == "prod" ? "production" : local.env.environment == "uat" ? "staging" : local.env.environment == "ti" ? "staging" : "development"
  deployment_bucket = module.s3.buckets["deployment"].bucket
}

# MQ
module "mq-ingest" {
  source = "./MQ/ingest"

  environment               = local.env.environment
  mq_ingest_subnets         = [module.vpc.subnet_private_a.id]
  mq_ingest_security_groups = [module.security-groups.rabbitmq.id]
  mq_ingest_secret_string   = module.secrets-manager.secret_strings["ingest-mqsecret"]
}

# RDS
module "rds-ingest" {
  source = "./RDS/ingest"

  environment               = local.env.environment
  subnet-a                  = module.vpc.subnet_private_a.id
  subnet-b                  = module.vpc.subnet_private_b.id
  db_ingest_secret_string   = module.secrets-manager.secret_strings["ingest-pg-rdssecret"]
  rds_kms_key               = module.kms.key_arns["rds-ingest"]
  db_ingest_security_groups = [module.security-groups.rds.id]

  private_route_53_zone = module.private-route53.zone
}

module "rds-viz" {
  source = "./RDS/viz"

  environment                       = local.env.environment
  subnet-a                          = module.vpc.subnet_private_a.id
  subnet-b                          = module.vpc.subnet_private_b.id
  db_viz_processing_secret_string   = module.secrets-manager.secret_strings["viz-processing-pg-rdssecret"]
  rds_kms_key                       = module.kms.key_arns["rds-viz"]
  db_viz_processing_security_groups = [module.security-groups.rds.id]
  viz_db_name                       = local.env.viz_db_name
  role_rds_s3_export_arn            = module.iam-roles.role_rds_s3_export.arn

  private_route_53_zone = module.private-route53.zone
}

###################### STAGE 4 ###################### (Set up Deployment Bucket Artifacts and EGIS Resources before deploying)

# EGIS Route53 DNS
module "private-route53-egis" {
  source = "./Route53/private/egis"

  environment = local.env.environment
  region      = local.env.region
  vpc_main_id = module.vpc.vpc_main.id
}

module "rds-egis" {
  source = "./RDS/egis"

  environment = local.env.environment
  region      = local.env.region

  private_route_53_zone = module.private-route53.zone
}

module "rds-bastion" {
  source = "./EC2/RDSBastion"

  environment                    = local.env.environment
  region                         = local.env.region
  account_id                     = local.env.account_id
  ec2_instance_profile_name      = module.iam-roles.profile_data_ingest.name
  ec2_instance_subnet            = module.vpc.subnet_private_a.id
  ec2_instance_availability_zone = module.vpc.subnet_private_a.availability_zone
  ec2_instance_sgs = [
    module.security-groups.rds.id,
    module.security-groups.rabbitmq.id,
    module.security-groups.vpc_access.id
  ]
  kms_key_arn = module.kms.key_arns["encrypt-ec2"]

  data_deployment_bucket = module.s3.buckets["deployment"].bucket

  ingest_db_secret_string        = module.secrets-manager.secret_strings["ingest-pg-rdssecret"]
  ingest_db_address              = module.rds-ingest.dns_name
  ingest_db_port                 = module.rds-ingest.instance.port
  nwm_viz_ro_secret_string       = module.secrets-manager.secret_strings["rds-nwm-viz-ro"]
  rfc_fcst_secret_string         = module.secrets-manager.secret_strings["rds-rfc-fcst"]
  rfc_fcst_ro_user_secret_string = module.secrets-manager.secret_strings["data-services-forecast-pg-rdssecret"]
  rfc_fcst_user_secret_string    = module.secrets-manager.secret_strings["rds-rfc-fcst-user"]
  location_ro_user_secret_string = module.secrets-manager.secret_strings["data-services-location-pg-rdssecret"]
  location_db_name               = local.env.location_db_name
  forecast_db_name               = local.env.forecast_db_name

  ingest_mq_secret_string = module.secrets-manager.secret_strings["ingest-mqsecret"]
  ingest_mq_endpoint      = module.mq-ingest.mq-ingest.instances.0.endpoints.0

  viz_proc_admin_rw_secret_string = module.secrets-manager.secret_strings["viz-proc-admin-rw-user"]
  viz_proc_admin_rw_secret_arn    = module.secrets-manager.secret_arns["viz-proc-admin-rw-user"]
  viz_proc_dev_rw_secret_string   = module.secrets-manager.secret_strings["viz-proc-dev-rw-user"]
  viz_db_secret_string            = module.secrets-manager.secret_strings["viz-processing-pg-rdssecret"]
  viz_db_address                  = module.rds-viz.instance.address
  viz_db_port                     = module.rds-viz.instance.port
  viz_db_name                     = local.env.viz_db_name
  egis_db_master_secret_string    = module.secrets-manager.secret_strings["egis-master-pg-rds-secret"]
  egis_db_secret_string           = module.secrets-manager.secret_strings["egis-pg-rds-secret"]
  egis_db_address                 = module.rds-egis.dns_name
  egis_db_port                    = module.rds-egis.instance.port
  egis_db_name                    = local.env.egis_db_name

  fim_version = local.env.fim_version
}

# Data Services (WRDS APIs)
module "data-services" {
  source = "./EC2/DataServices"

  environment                    = local.env.environment
  region                         = local.env.region
  account_id                     = local.env.account_id
  ec2_instance_subnet            = module.vpc.subnet_private_a.id
  ec2_instance_availability_zone = module.vpc.subnet_private_a.availability_zone
  ec2_instance_sgs = [
    module.security-groups.rds.id,
    module.security-groups.vpc_access.id,
  ]
  ec2_instance_profile_name          = module.iam-roles.profile_data_services.name
  kms_key_arn                        = module.kms.key_arns["encrypt-ec2"]
  rds_host                           = module.rds-ingest.dns_name
  location_db_name                   = local.env.location_db_name
  forecast_db_name                   = local.env.forecast_db_name
  location_credentials_secret_string = module.secrets-manager.secret_strings["data-services-location-pg-rdssecret"]
  forecast_credentials_secret_string = module.secrets-manager.secret_strings["data-services-forecast-pg-rdssecret"]
  vlab_repo_prefix                   = local.env.data_services_vlab_repo_prefix
  data_services_versions             = local.env.data_services_versions

  private_route_53_zone = module.private-route53.zone
}

module "ingest-lambda-functions" {
  source = "./LAMBDA/ingest_functions"
  providers = {
    aws     = aws
    aws.sns = aws.sns
  }

  environment                 = local.env.environment
  region                      = local.env.region
  deployment_bucket           = module.s3.buckets["deployment"].bucket
  lambda_role                 = module.iam-roles.role_data_ingest.arn
  psycopg2_sqlalchemy_layer   = module.lambda-layers.psycopg2_sqlalchemy.arn
  pika_layer                  = module.lambda-layers.pika.arn
  rfc_fcst_user_secret_string = module.secrets-manager.secret_strings["rds-rfc-fcst-user"]
  mq_ingest_id                = module.mq-ingest.mq-ingest.id
  db_ingest_name              = local.env.forecast_db_name
  db_ingest_host              = module.rds-ingest.dns_name
  mq_ingest_port              = split(":", module.mq-ingest.mq-ingest.instances.0.endpoints.0)[2]
  db_ingest_port              = module.rds-ingest.instance.port
  primary_hml_bucket_name     = module.s3-replication.buckets["hml"].bucket
  primary_hml_bucket_arn      = module.s3-replication.buckets["hml"].arn
  backup_hml_bucket_name      = module.s3.buckets["hml-backup"].bucket
  backup_hml_bucket_arn       = module.s3.buckets["hml-backup"].arn
  lambda_subnet_ids           = [module.vpc.subnet_private_a.id, module.vpc.subnet_private_b.id]
  lambda_security_group_ids   = [module.security-groups.vpc_access.id]
  nws_shared_account_hml_sns  = local.env.nws_shared_account_hml_sns
}

# Data Ingest
module "data-ingest-ec2" {
  source = "./EC2/Ingest"

  environment            = local.env.environment
  region                 = local.env.region
  account_id             = local.env.account_id
  prc1_subnet            = module.vpc.subnet_private_a.id
  prc2_subnet            = module.vpc.subnet_private_b.id
  prc1_availability_zone = module.vpc.subnet_private_a.availability_zone
  prc2_availability_zone = module.vpc.subnet_private_b.availability_zone
  ec2_instance_sgs = [
    module.security-groups.rds.id,
    module.security-groups.rabbitmq.id,
    module.security-groups.vpc_access.id
  ]
  ec2_kms_key               = module.kms.key_arns["encrypt-ec2"]
  ec2_instance_profile_name = module.iam-roles.profile_data_ingest.name
  deployment_bucket         = module.s3.buckets["deployment"].bucket

  mq_ingest_endpoint      = module.mq-ingest.mq-ingest.instances.0.endpoints.0
  mq_ingest_secret_string = module.secrets-manager.secret_strings["rds-rfc-fcst-user"]
  db_host                 = module.rds-ingest.dns_name
  db_ingest_secret_string = module.secrets-manager.secret_strings["rds-rfc-fcst-user"]
}

module "rnr" {
  source = "./EC2/rnr"

  environment                    = local.env.environment
  region                         = local.env.region
  account_id                     = local.env.account_id
  ec2_instance_subnet            = module.vpc.subnet_private_a.id
  ec2_instance_availability_zone = module.vpc.subnet_private_a.availability_zone
  ec2_instance_sgs               = [module.security-groups.vpc_access.id]
  output_bucket                  = module.s3.buckets["rnr"].bucket
  deployment_bucket              = module.s3.buckets["deployment"].bucket
  ec2_kms_key                    = module.kms.key_arns["encrypt-ec2"]
  ec2_instance_profile_name      = module.iam-roles.profile_rnr.name
  dataservices_host              = module.data-services.dns_name
  nomads_url                     = local.env.nwm_dataflow_version == "para" ? local.env.rnr_para_nomads_url : local.env.rnr_prod_nomads_url
  s3_url                         = local.env.nwm_dataflow_version == "para" ? local.env.rnr_para_s3_url : local.env.rnr_prod_s3_url
  rnr_versions                   = local.env.rnr_versions
}

# RnR Lambda Functions
module "rnr-lambda-functions" {
  source = "./LAMBDA/rnr_functions"
  providers = {
    aws     = aws
    aws.sns = aws.sns
  }

  environment                   = local.env.environment
  region                        = local.env.region
  rnr_data_bucket               = module.s3.buckets["rnr"].bucket
  deployment_bucket             = module.s3.buckets["deployment"].bucket
  lambda_role                   = module.iam-roles.role_viz_pipeline.arn
  xarray_layer                  = module.lambda-layers.xarray.arn
  psycopg2_sqlalchemy_layer     = module.lambda-layers.psycopg2_sqlalchemy.arn
  viz_lambda_shared_funcs_layer = module.lambda-layers.viz_lambda_shared_funcs.arn
  db_lambda_security_groups     = [module.security-groups.rds.id, module.security-groups.egis_overlord.id]
  db_lambda_subnets             = [module.vpc.subnet_private_a.id, module.vpc.subnet_private_b.id]
  viz_db_host                   = module.rds-viz.dns_name
  viz_db_name                   = local.env.viz_db_name
  viz_db_user_secret_string     = module.secrets-manager.secret_strings["viz-proc-admin-rw-user"]
}

module "egis-license-manager" {
  source = "./EC2/LicenseManager"

  environment                    = local.env.environment
  account_id                     = local.env.account_id
  region                         = local.env.region
  ec2_instance_subnet            = module.vpc.subnet_private_a.id
  ec2_instance_availability_zone = module.vpc.subnet_private_a.availability_zone
  ec2_instance_sgs = [
    module.security-groups.vpc_access.id,
    module.security-groups.egis_overlord.id
  ]
  ec2_instance_profile_name = module.iam-roles.profile_HydrovisESRISSMDeploy.name
  ec2_kms_key               = module.kms.key_arns["egis"]

  private_route_53_zone = module.private-route53.zone
}

module "egis-monitor" {
  source = "./EC2/ArcGIS_Monitor"

  environment                    = local.env.environment
  account_id                     = local.env.account_id
  region                         = local.env.region
  ec2_instance_subnet            = module.vpc.subnet_private_a.id
  ec2_instance_availability_zone = module.vpc.subnet_private_a.availability_zone
  ec2_instance_sgs = [
    module.security-groups.vpc_access.id,
    module.security-groups.egis_overlord.id
  ]
  ec2_instance_profile_name = module.iam-roles.profile_HydrovisESRISSMDeploy.name
  ec2_kms_key               = module.kms.key_arns["egis"]
}

module "cloudwatch" {
  source = "./CloudWatch"

  environment = local.env.environment
  account_id  = local.env.account_id
  region      = local.env.region
}

###################### STAGE 4 ###################### (Wait till all other EC2 are initialized and running)

# Viz Lambda Functions
module "viz-lambda-functions" {
  source = "./LAMBDA/viz_functions"
  providers = {
    aws     = aws
    aws.sns = aws.sns
  }

  environment                    = local.env.environment
  account_id                     = local.env.account_id
  region                         = local.env.region
  viz_authoritative_bucket       = module.s3.buckets["deployment"].bucket
  fim_data_bucket                = module.s3.buckets["deployment"].bucket
  fim_output_bucket              = module.s3.buckets["fim"].bucket
  python_preprocessing_bucket    = module.s3.buckets["fim"].bucket
  rnr_data_bucket                = module.s3.buckets["rnr"].bucket
  deployment_bucket              = module.s3.buckets["deployment"].bucket
  viz_cache_bucket               = module.s3.buckets["fim"].bucket
  fim_version                    = local.env.fim_version
  lambda_role                    = module.iam-roles.role_viz_pipeline.arn
  # sns_topics                      = module.sns.sns_topics
  nws_shared_account_nwm_sns     = local.env.nwm_dataflow_version == "para" ? local.env.nws_shared_account_para_nwm_sns : local.env.nws_shared_account_prod_nwm_sns
  email_sns_topics               = module.sns.email_sns_topics
  es_logging_layer               = module.lambda-layers.es_logging.arn
  xarray_layer                   = module.lambda-layers.xarray.arn
  pandas_layer                   = module.lambda-layers.pandas.arn
  geopandas_layer                = module.lambda-layers.geopandas.arn
  arcgis_python_api_layer        = module.lambda-layers.arcgis_python_api.arn
  psycopg2_sqlalchemy_layer      = module.lambda-layers.psycopg2_sqlalchemy.arn
  requests_layer                 = module.lambda-layers.requests.arn
  yaml_layer                     = module.lambda-layers.yaml.arn
  dask_layer                     = module.lambda-layers.dask.arn
  viz_lambda_shared_funcs_layer  = module.lambda-layers.viz_lambda_shared_funcs.arn
  db_lambda_security_groups      = [module.security-groups.rds.id, module.security-groups.egis_overlord.id]
  nat_sg_group                   = module.security-groups.vpc_access.id
  db_lambda_subnets              = [module.vpc.subnet_private_a.id, module.vpc.subnet_private_b.id]
  viz_db_host                    = module.rds-viz.dns_name
  viz_db_name                    = local.env.viz_db_name
  viz_db_user_secret_string      = module.secrets-manager.secret_strings["viz-proc-admin-rw-user"]
  egis_db_host                   = module.rds-egis.dns_name
  egis_db_name                   = local.env.egis_db_name
  egis_db_user_secret_string     = module.secrets-manager.secret_strings["egis-pg-rds-secret"]
  egis_portal_password           = local.env.viz_ec2_hydrovis_egis_pass
  dataservices_host              = module.data-services.dns_name
  viz_pipeline_step_function_arn = module.step-functions.viz_pipeline_step_function.arn
  default_tags                   = local.env.tags
  nwm_dataflow_version           = local.env.nwm_dataflow_version
  five_minute_trigger            = module.eventbridge.five_minute_eventbridge
}

module "step-functions" {
  source = "./StepFunctions"

  viz_lambda_role                   = module.iam-roles.role_viz_pipeline.arn
  rnr_lambda_role                   = module.iam-roles.role_sync_wrds_location_db.arn
  environment                       = local.env.environment
  optimize_rasters_arn              = module.viz-lambda-functions.optimize_rasters.arn
  update_egis_data_arn              = module.viz-lambda-functions.update_egis_data.arn
  fim_data_prep_arn                 = module.viz-lambda-functions.fim_data_prep.arn
  db_postprocess_sql_arn            = module.viz-lambda-functions.db_postprocess_sql.arn
  db_ingest_arn                     = module.viz-lambda-functions.db_ingest.arn
  raster_processing_arn             = module.viz-lambda-functions.raster_processing.arn
  publish_service_arn               = module.viz-lambda-functions.publish_service.arn
  python_preprocessing_3GB_arn      = module.viz-lambda-functions.python_preprocessing_3GB.arn
  python_preprocessing_10GB_arn     = module.viz-lambda-functions.python_preprocessing_10GB.arn
  hand_fim_processing_arn           = module.viz-lambda-functions.hand_fim_processing.arn
  schism_fim_job_definition_arn     = module.viz-lambda-functions.schism_fim.job_definition.arn
  schism_fim_job_queue_arn          = module.viz-lambda-functions.schism_fim.job_queue.arn
  initialize_pipeline_arn           = module.viz-lambda-functions.initialize_pipeline.arn
  rnr_domain_generator_arn          = module.rnr-lambda-functions.rnr_domain_generator.arn
  email_sns_topics                  = module.sns.email_sns_topics
  aws_instances_to_reboot           = [module.rnr.ec2.id]
  fifteen_minute_trigger            = module.eventbridge.fifteen_minute_eventbridge
  viz_processing_pipeline_log_group = module.cloudwatch.viz_processing_pipeline_log_group.name
}

# Event Bridge
module "eventbridge" {
  source = "./EventBridge"
}

module "viz-ec2" {
  source = "./EC2/viz"

  environment                    = local.env.environment
  account_id                     = local.env.account_id
  region                         = local.env.region
  ec2_instance_subnet            = module.vpc.subnet_private_a.id
  ec2_instance_availability_zone = module.vpc.subnet_private_a.availability_zone
  ec2_instance_sgs = [
    module.security-groups.vpc_access.id,
    module.security-groups.egis_overlord.id
  ]
  fim_data_bucket             = module.s3.buckets["deployment"].bucket
  fim_output_bucket           = module.s3.buckets["fim"].bucket
  nwm_data_bucket             = local.env.nws_shared_account_s3_bucket
  python_preprocessing_bucket = module.s3.buckets["fim"].bucket
  rnr_data_bucket             = module.s3.buckets["rnr"].bucket
  deployment_data_bucket      = module.s3.buckets["deployment"].bucket
  kms_key_arn                 = module.kms.key_arns["egis"]
  ec2_instance_profile_name   = module.iam-roles.profile_HydrovisESRISSMDeploy.name
  windows_service_status      = local.env.viz_ec2_windows_service_status
  windows_service_startup     = local.env.viz_ec2_windows_service_startup
  license_server_host         = module.egis-license-manager.dns_name
  pipeline_user_secret_string = module.secrets-manager.secret_strings["egis-service-account"]
  hydrovis_egis_pass          = local.env.viz_ec2_hydrovis_egis_pass
  github_repo_prefix          = local.env.viz_ec2_github_repo_prefix
  github_host                 = local.env.viz_ec2_github_host
  viz_db_host                 = module.rds-viz.dns_name
  viz_db_name                 = local.env.viz_db_name
  viz_db_user_secret_string   = module.secrets-manager.secret_strings["viz-proc-admin-rw-user"]
  egis_db_host                = module.rds-egis.dns_name
  egis_db_name                = local.env.egis_db_name
  egis_db_secret_string       = module.secrets-manager.secret_strings["egis-pg-rds-secret"]
  private_route_53_zone       = module.private-route53.zone
  nwm_dataflow_version        = local.env.nwm_dataflow_version
}

module "sync-wrds-location-db" {
  source = "./SyncWrdsLocationDB"

  environment            = local.env.environment
  region                 = local.env.region
  iam_role_arn           = module.iam-roles.role_sync_wrds_location_db.arn
  email_sns_topics       = module.sns.email_sns_topics
  requests_lambda_layer  = module.lambda-layers.requests.arn
  rds_bastion_id         = module.rds-bastion.instance-id
  test_data_services_id  = module.data-services.dataservices-test-instance-id
  lambda_security_groups = [module.security-groups.rds.id]
  lambda_subnets         = [module.vpc.subnet_private_a.id, module.vpc.subnet_private_b.id]
  db_dumps_bucket        = module.s3.buckets["deployment"].bucket
}
