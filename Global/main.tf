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

# See sensitive/envs/env.ENV_global.yaml to select the "active region" for the environment
locals {
  env = merge(
    yamldecode(file("../Core/sensitive/envs/us-east-1/env.${split("_", terraform.workspace)[0]}.yaml")),
    yamldecode(file("../Core/sensitive/envs/env.${terraform.workspace}.yaml"))
  )

  wacky_egis_alb_names = {
    us-east-1 = {
      uat = "hv-uat-pub-lb-pub-age-alb"
      prod = "hv-prod-pub-lb-alb-pub-age-alb"
    }
    us-east-2 = {
      uat = "hv-uat-egis-pub-lb-pub-age-alb"
      prod = "hv-prod-pub-lb-alb-pub-age-alb"
    }
  }
}


# Default Provider
provider "aws" {
  region                   = "us-east-1"
  profile                  = local.env.environment
  shared_credentials_files = ["/cloud/aws/credentials"]

  default_tags {
    tags = merge(local.env.tags, {
      CreatedBy = "Terraform"
    })
  }
}


# Region-specific Providers
provider "aws" {
  alias                    = "us-east-1"
  region                   = "us-east-1"
  profile                  = local.env.environment
  shared_credentials_files = ["/cloud/aws/credentials"]
}
provider "aws" {
  alias                    = "us-east-2"
  region                   = "us-east-2"
  profile                  = local.env.environment
  shared_credentials_files = ["/cloud/aws/credentials"]
}


# EGIS ALB for each region
data "aws_lb" "egis_alb_us-east-1" {
  provider = aws.us-east-1
  name     = local.wacky_egis_alb_names["us-east-1"][local.env.environment]
}
data "aws_lb" "egis_alb_us-east-2" {
  provider = aws.us-east-2
  name     = local.wacky_egis_alb_names["us-east-2"][local.env.environment]
}


# Route53 DNS
module "public-route53" {
  source = "./Route53/public"
  environment   = local.env.environment
  account_id    = local.env.account_id
  active_region = local.env.active_region

  egis_health_checks = {
    us-east-1 = {
      alarm_name  = "uat_egis_healthcheck"
      alb_host    = data.aws_lb.egis_alb_us-east-1.dns_name
      alb_zone_id = data.aws_lb.egis_alb_us-east-1.zone_id
    }
    us-east-2 = {
      alarm_name  = "uat_egis_healthcheck"
      alb_host    = data.aws_lb.egis_alb_us-east-2.dns_name
      alb_zone_id = data.aws_lb.egis_alb_us-east-2.zone_id
    }
  }
}