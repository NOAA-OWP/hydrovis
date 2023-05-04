variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_main_id" {
  type = string
}


locals {
  zone_names = {
    ti = "maps-testing.water.noaa.gov"
    uat = "maps-staging.water.noaa.gov"
    prod = "maps.water.noaa.gov"
  }

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

resource "aws_route53_zone" "private" {
  name = local.zone_names[var.environment]

  vpc {
    vpc_id = var.vpc_main_id
  }
}

data "aws_lb" "public" {
  name = local.wacky_egis_alb_names[var.region][var.environment]
}

resource "aws_route53_record" "egis_alb" {
  zone_id = aws_route53_zone.private.zone_id
  name    = aws_route53_zone.private.name
  type    = "A"

  alias {
    evaluate_target_health = true
    name                   = "dualstack.${data.aws_lb.public.dns_name}"
    zone_id                = data.aws_lb.public.zone_id
  }
}


output "zone" {
  value = {
    name    = aws_route53_zone.private.name
    zone_id = aws_route53_zone.private.zone_id
  }
}