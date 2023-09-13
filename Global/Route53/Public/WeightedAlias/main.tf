variable "aliases" {
  type = any
}

variable "zone" {
  type = any
}


resource "aws_route53_record" "aliases" {
  for_each = var.aliases["records"]

  zone_id = var.zone.id
  name    = var.aliases["url"]
  type    = "A"

  alias {
    evaluate_target_health = false
    # evaluate_target_health = true
    name                   = each.value["alb_host"]
    zone_id                = each.value["alb_zone_id"]
  }

  weighted_routing_policy {
    weight = var.aliases["active_region"] == each.key ? 255 : 0
  }

  set_identifier = each.key
  # health_check_id = aws_route53_health_check.egis_health_check[each.key].id
}

# Health Check and Failover DNS Records
# resource "aws_route53_health_check" "egis_health_check" {
#   for_each = var.egis_health_checks

#   type                            = "CLOUDWATCH_METRIC"
#   cloudwatch_alarm_name           = each.value["alarm_name"]
#   cloudwatch_alarm_region         = each.key
#   insufficient_data_health_status = "LastKnownStatus"

#   tags = {
#     Name = "egis-health-check-${each.key}"
#   }
# }

# resource "aws_route53_record" "region_aliases" {
#   for_each = var.aliases["records"]

#   zone_id = var.zone.id
#   name    = "${each.key}.${var.aliases["url"]}"
#   type    = "A"

#   alias {
#     evaluate_target_health = false
#     name                   = each.value["alb_host"]
#     zone_id                = each.value["alb_zone_id"]
#   }
# }