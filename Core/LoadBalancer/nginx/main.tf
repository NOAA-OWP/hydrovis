variable "environment" {
  type = string
}

varible "security_groups" {
    type = list(string)
}

variable "subnets" {
    type = list(string)
}

variable "vpc" {
    type = string
}

variable "certificate_arn" {
    type = string
}

resource "aws_lb" "kibana_private" {
    name = "hv-${var.environment}-prv-kibana-nginx-alb"
    internal = true
    load_balancer_type = "application"
    security_groups = var.security_groups
    subnets = var.subnets
    ip_address_type = "ipv4"
}

resource "aws_lb_target_group" "kibana_nginx_target_group" {
    name = "hv-${var.environment}-kibana-nginx-albtg"
    port = 80
    protocol = "HTTP"
    target_type = "ip"
    vpc_id = var.vpc

    health_check {
      enabled = true
      healthy_threshold = 3
      interval = 30
      matcher = "200"
      path = "/health"
      unhealthy_threshold = 2
    }
}

resource "aws_lb_listener" "kibana_nginx_listener" {
    load_balancer_arn = aws_lb.kibana_private.arn
    port = "443"
    protocol = "HTTPS"
    ssl_policy = "ELBSecurityPolicy-FS-1-2-Res-2019-08"
    certificate_arn = var.certificate_arn

    default_action {
      type = "forward"
      target_group_arn = aws_lb_target_group.kibana_nginx_target_group.arn
    }
}

output "aws_lb_kibana_nginx_private" {
  value = aws_lb.kibana_private
}

output "aws_lb_target_group_kibana_ngninx" {
  value = aws_lb_target_group.kibana_nginx_target_group
}

output "aws_lb_listener_kibana_nginx" {
  value = aws_lb_listener.kibana_nginx_listener
}