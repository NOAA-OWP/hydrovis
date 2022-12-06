variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "domain_endpoint" {
  type = string
}

variable "deployment_bucket" {
  type = string
}

variable "data_subnet_ids" {
  type = list(string)
}

variable "opensearch_security_group_ids" {
  type = list(string)
}

variable "vpc_id" {
  type = string
}

variable "task_role_arn" {
  type = string
}

variable "execution_role_arn" {
  type = string
}



# Create the Public Load Balancer Rule
data "aws_lb" "hydrovis_public_lb" {
  name = "hv-${var.environment}-egis-pub-prtl-alb"
}

data "aws_lb_listener" "hydrovis_443_listener" {
  load_balancer_arn = data.aws_lb.hydrovis_public_lb.arn
  port              = 443
}

resource "aws_lb_target_group" "opensearch_nginx_target_group" {
    name = "hv-${var.environment}-opensearch-nginx-albtg"
    port = 80
    protocol = "HTTP"
    target_type = "ip"
    vpc_id = var.vpc_id

    health_check {
      enabled = true
      healthy_threshold = 3
      interval = 30
      matcher = "200"
      path = "/health"
      unhealthy_threshold = 2
    }
}

resource "aws_lb_listener_rule" "opensearch_listener" {
  listener_arn = data.aws_lb_listener.hydrovis_443_listener.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.opensearch_nginx_target_group.arn
  }

  condition {
    path_pattern {
      values = ["/dashboards", "/dashboards/*", "/_dashboards", "/_dashboards/*"]
    }
  }
}

resource "aws_ecs_cluster" "hydrovis" {
  name = "hydrovis-${var.environment}-fargate-cluster"
}


# Nginx Config
resource "aws_s3_object" "nginx_config" {
  bucket      = var.deployment_bucket
  key         = "ecs/nginx/default.conf.template"
  source      = "${path.module}/default.conf.template"
  source_hash = filemd5("${path.module}/default.conf.template")
}

# Nginx Proxy OpenSearch to the Load Balancer
resource "aws_ecs_task_definition" "nginx_proxy" {
  family = "nginx_proxy"

  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512

  task_role_arn      = var.task_role_arn
  execution_role_arn = var.execution_role_arn

  container_definitions = jsonencode([
    {
      name      = "nginx"
      image     = "nginx:mainline-alpine"
      essential = true
      dependsOn = [
        {
          containerName = "nginx-config"
          condition     = "COMPLETE"
        }
      ]
      portMappings = [
        {
          containerPort = 80
          protocol      = "tcp"
        }
      ]
      mountPoints = [
        {
          containerPath = "/etc/nginx/templates"
          sourceVolume  = "nginx_template"
        }
      ]
      environment = [
        {
          name  = "OS_DOMAIN"
          value = "${var.domain_endpoint}"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "hydrovis-${var.environment}-fargate-logs"
          awslogs-region        = "${var.region}"
          awslogs-create-group  = "true"
          awslogs-stream-prefix = "hydrovis-${var.environment}-fargate"
        }
      }
    },
    {
      name      = "nginx-config"
      image     = "amazon/aws-cli:latest"
      essential = false
      command = [
        "s3",
        "cp",
        "s3://${var.deployment_bucket}/${aws_s3_object.nginx_config.key}",
        "/etc/nginx/templates"
      ]
      mountPoints = [
        {
          containerPath = "/etc/nginx/templates"
          sourceVolume  = "nginx_template"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "hydrovis-${var.environment}-fargate-logs"
          awslogs-region        = "${var.region}"
          awslogs-create-group  = "true"
          awslogs-stream-prefix = "hydrovis-${var.environment}-fargate"
        }
      }
    }
  ])
  volume {
    name = "nginx_template"
  }

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

}

resource "aws_ecs_service" "opensearch_nginx" {
  name                              = "hydrovis-${var.environment}-opensearch-nginx-proxy"
  cluster                           = aws_ecs_cluster.hydrovis.id
  task_definition                   = aws_ecs_task_definition.nginx_proxy.arn
  desired_count                     = 1
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 10

  load_balancer {
    target_group_arn = aws_lb_target_group.opensearch_nginx_target_group.arn
    container_name = "nginx"
    container_port = 80
  }

  network_configuration {
    subnets = var.data_subnet_ids
    security_groups = var.opensearch_security_group_ids
  }
}