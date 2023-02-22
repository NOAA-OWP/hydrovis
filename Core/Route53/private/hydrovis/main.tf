variable "vpc_main_id" {
  type = string
}

resource "aws_route53_zone" "private" {
  name = "hydrovis.internal"

  vpc {
    vpc_id = var.vpc_main_id
  }
}

output "zone" {
  value = {
    name    = aws_route53_zone.private.name
    zone_id = aws_route53_zone.private.zone_id
  }
}