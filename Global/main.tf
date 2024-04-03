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
    yamldecode(file("../Core/sensitive/vpp/envs/us-east-1/env.${split("_", terraform.workspace)[0]}.yaml")),
    yamldecode(file("../Core/sensitive/vpp/envs/env.${terraform.workspace}.yaml"))
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
  alias                    = "uat_us-east-1"
  region                   = "us-east-1"
  profile                  = "uat"
  shared_credentials_files = ["/cloud/aws/credentials"]
}
provider "aws" {
  alias                    = "uat_us-east-2"
  region                   = "us-east-2"
  profile                  = "uat"
  shared_credentials_files = ["/cloud/aws/credentials"]
}
provider "aws" {
  alias                    = "prod_us-east-1"
  region                   = "us-east-1"
  profile                  = "prod"
  shared_credentials_files = ["/cloud/aws/credentials"]
}
provider "aws" {
  alias                    = "prod_us-east-2"
  region                   = "us-east-2"
  profile                  = "prod"
  shared_credentials_files = ["/cloud/aws/credentials"]
}


# EGIS ALBs
data "aws_lb" "egis_alb_uat_us-east-1" {
  provider = aws.uat_us-east-1
  name     = local.wacky_egis_alb_names["us-east-1"]["uat"]
}
data "aws_lb" "egis_alb_uat_us-east-2" {
  provider = aws.uat_us-east-2
  name     = local.wacky_egis_alb_names["us-east-2"]["uat"]
}
data "aws_lb" "egis_alb_prod_us-east-1" {
  provider = aws.prod_us-east-1
  name     = local.wacky_egis_alb_names["us-east-1"]["prod"]
}
data "aws_lb" "egis_alb_prod_us-east-2" {
  provider = aws.prod_us-east-2
  name     = local.wacky_egis_alb_names["us-east-2"]["prod"]
}

# NWPS ALBs
data "aws_lb" "nwps_alb_uat_us-east-1" {
  provider = aws.uat_us-east-1
  name     = "hv-uat-nwps-alb"
}


# Route53 DNS
module "public-route53" {
  source = "./Route53/public"
  account_id    = local.env.account_id

  dns_records = {
    domain = "water.noaa.gov"
    weighted_alias = {
      maps_staging = {
        active_region = local.env.vpp_uat_active_region
        url = "maps-staging.water.noaa.gov"
        records = {
          us-east-1 = {
            alarm_name  = "uat_egis_healthcheck"
            alb_host    = "dualstack.${data.aws_lb.egis_alb_uat_us-east-1.dns_name}"
            alb_zone_id = data.aws_lb.egis_alb_uat_us-east-1.zone_id
          }
          us-east-2 = {
            alarm_name  = "uat_egis_healthcheck"
            alb_host    = "dualstack.${data.aws_lb.egis_alb_uat_us-east-2.dns_name}"
            alb_zone_id = data.aws_lb.egis_alb_uat_us-east-2.zone_id
          }
        }
      }
      maps = {
        active_region = local.env.vpp_prod_active_region
        url = "maps.water.noaa.gov"
        records = {
          us-east-1 = {
            alarm_name  = "prod_egis_healthcheck"
            alb_host    = "dualstack.${data.aws_lb.egis_alb_prod_us-east-1.dns_name}"
            alb_zone_id = data.aws_lb.egis_alb_prod_us-east-1.zone_id
          }
          us-east-2 = {
            alarm_name  = "prod_egis_healthcheck"
            alb_host    = "dualstack.${data.aws_lb.egis_alb_prod_us-east-2.dns_name}"
            alb_zone_id = data.aws_lb.egis_alb_prod_us-east-2.zone_id
          }
        }
      }
    }
    alias = {
      "preview.water.noaa.gov" = {
        alb_host    = data.aws_lb.nwps_alb_uat_us-east-1.dns_name
        alb_zone_id = data.aws_lb.nwps_alb_uat_us-east-1.zone_id
      }
      "preview-api.water.noaa.gov" = {
        alb_host    = data.aws_lb.nwps_alb_uat_us-east-1.dns_name
        alb_zone_id = data.aws_lb.nwps_alb_uat_us-east-1.zone_id
      }
      "preview-cms.water.noaa.gov" = {
        alb_host    = data.aws_lb.nwps_alb_uat_us-east-1.dns_name
        alb_zone_id = data.aws_lb.nwps_alb_uat_us-east-1.zone_id
      }
    }
    a = {
      "water.noaa.gov" = local.env.nwps_a_redirect_ip
    }
    cname = {
      www = "water.noaa.gov"
    }
  }
}
