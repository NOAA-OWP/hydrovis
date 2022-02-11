variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "es_domain_endpoint" {
  type = string
}

variable "deployment_bucket" {
  type = string
}

variable "load_balancer_tg" {
  type = string
}

variable "subnets" {
  type = list(string)
}

variable "security_groups" {
  type = list(string)
}

variable "iam_role_arn" {
  type = string
}

variable "ecs_execution_role" {
  type = string
}

resource "aws_ecs_cluster" "hydrovis_fargate" {
  name = "hydrovis-${var.environment}-fargate-cluster"
}

resource "aws_ecs_task_definition" "kibana_nginx_proxy" {
  family = "kibana_nginx_proxy"

  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512

  task_role_arn      = var.iam_role_arn
  execution_role_arn = var.ecs_execution_role

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
          name  = "KIBANA_URL"
          value = "${var.kibana_endpoint}"
        }
      ]
      logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group = "hydrovis-${var.environment}-fargate-logs"
            awslogs-region = "${var.region}"
            awslogs-create-group = "true"
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
        "s3://${var.deployment_bucket}/ecs/nginx/default.conf.template", 
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
            awslogs-group = "hydrovis-${var.environment}-fargate-logs"
            awslogs-region = "${var.region}"
            awslogs-create-group = "true"
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

resource "aws_ecs_service" "kibana_nginx" {
  name                              = "hydrovis-${var.environment}-kibana-nginx-ecs-service"
  cluster                           = aws_ecs_cluster.hydrovis_fargate.id
  task_definition                   = aws_ecs_task_definition.kibana_nginx_proxy.arn
  desired_count                     = 1
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 10

  load_balancer {
    target_group_arn = var.load_balancer_tg
    container_name = "nginx"
    container_port = 80
  }

  network_configuration {
    subnets = var.subnets
    security_groups = var.security_groups
  }
}