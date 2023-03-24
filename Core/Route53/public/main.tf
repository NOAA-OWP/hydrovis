variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "r53_public_zone_id" {
  type = string
}

variable "egis_health_checker_alarm" {
  type = string
}


locals {
  zone_names = {
    ti = "maps-testing.water.noaa.gov"
    uat = "maps-staging.water.noaa.gov"
    prod = "maps.water.noaa.gov"
  }
}

data "aws_lb" "public" {
  name = "hv-${var.environment}-egis-pub-lb-pub-age-alb"
}

resource "aws_route53_health_check" "egis_health_check" {
  type                            = "CLOUDWATCH_METRIC"
  cloudwatch_alarm_name           = var.egis_health_checker_alarm.alarm_name
  cloudwatch_alarm_region         = var.region
  insufficient_data_health_status = "LastKnownStatus"

  tags = {
    Name = "egis-health-check-${var.region}"
  }
}

resource "aws_route53_record" "egis_alb" {
  zone_id = var.r53_public_zone_id
  name    = local.zone_names[var.environment]
  type    = "A"

  alias {
    evaluate_target_health = true
    name                   = "dualstack.${data.aws_lb.public.dns_name}"
    zone_id                = data.aws_lb.public.zone_id
  }

  weighted_routing_policy {
    weight = var.region == "us-east-1" ? 255 : 0
  }

  set_identifier = var.region
  health_check_id = aws_route53_health_check.egis_health_check.id
}