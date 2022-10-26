variable "vpc_main_id" {
  type = string
}

resource "aws_route53_zone" "hydrovis_internal" {
  name = "hydrovis.internal"


  vpc {
    vpc_id = var.vpc_main_id
  }
}

output "hydrovis_internal_zone" {
  value = aws_route53_zone.hydrovis_internal
}