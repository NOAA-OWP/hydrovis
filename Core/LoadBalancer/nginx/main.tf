variable "environment" {
  type = string
}

variable "security_groups" {
  type = list(string)
}

variable "subnets" {
    type = list(string)
}

variable "vpc" {
    type = string
}

data "aws_lb" "hydrovis_public_lb" {
  name = "hv-${var.environment}-egis-pub-prtl-alb"
}

data "aws_lb_listener" "hydrovis_443_listener" {
  load_balancer_arn = data.aws_lb.hydrovis_public_lb.arn
  port              = 443
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

resource "aws_lb_listener_rule" "kibana_listener" {
  listener_arn = data.aws_lb_listener.hydrovis_443_listener.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kibana_nginx_target_group.arn
  }

  condition {
    path_pattern {
      values = ["/kibana", "/kibana/*", "/_plugin/kibana", "/_plugin/kibana/*"]
    }
  }
}

output "aws_lb_target_group_kibana_ngninx" {
  value = aws_lb_target_group.kibana_nginx_target_group
}

output "aws_lb_listener_rule_kibana_listener" {
  value = aws_lb_listener_rule.kibana_listener
}
