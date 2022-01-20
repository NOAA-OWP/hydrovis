variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "availability_zone" {
  type = string
}

variable "kibana_endpoint" {
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

resource "aws_ecs_cluster" "hydrovis_fargate" {
  name = "hydrovis-${var.environment}-fargate-cluster"
}

resource "aws_ecs_task_definition" "kibana_nginx_proxy" {
  family = "kibana_nginx_proxy"

  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512

  container_definitions = jsonencode([
    {
      name      = "nginx"
      image     = "nginx:1.21.4-alpine"
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
          sourceVolune  = "nginx_template"
        }
      ]
      environment = [
        {
          name  = "KIBANA_URL"
          value = "${var.kibana_endpoint}"
        }
      ]
    },
    {
      name      = "nginx-config"
      image     = "amazon/aws-cli:2.4.7"
      essential = false
      command = [
        "-c",
        "aws s3 cp s3://$DEPLOYMENT_BUCKET/ecs/nginx/default.conf.template /etc/nginx/templates"
      ]
      environment = [
        {
          name  = "DEPLOYMENT_BUCKET"
          value = "${var.deployment_bucket}"
        }
      ]
      mountPoints = [
        {
          containerPath = "/etc/nginx/templates"
          sourceVolune  = "nginx_template"
        }
      ]
    }
  ])
  volume {
    name = "nginx_template"

    docker_volume_configuration {
      scope = "task"
    }
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
  desired_count                     = 2
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 10

  load_balancer {
    target_group_arn = var.load_balancer_tg
    container_name   = "nginx"
    container_port   = 80
  }

  network_configuration {
    subnets         = var.subnets
    security_groups = var.security_groups
  }
}