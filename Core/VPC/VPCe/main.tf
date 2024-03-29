variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_main_id" {
  type = string
}

variable "subnet_a_id" {
  type = string
}

variable "subnet_b_id" {
  type = string
}

variable "route_table_private_a_id" {
  type = string
}

variable "route_table_private_b_id" {
  type = string
}

variable "vpc_access_sg_id" {
  type = string
}


resource "aws_vpc_endpoint" "ec2messages" {
  private_dns_enabled = true
  security_group_ids = [
    var.vpc_access_sg_id,
  ]
  service_name = "com.amazonaws.${var.region}.ec2messages"
  subnet_ids = [
    var.subnet_a_id,
    var.subnet_b_id
  ]
  vpc_endpoint_type = "Interface"
  vpc_id            = var.vpc_main_id

  tags = {
    "Name" = "hv-vpp-${var.environment}-ec2messages"
  }
}

resource "aws_vpc_endpoint" "s3" {
  private_dns_enabled = false
  route_table_ids = [
    var.route_table_private_a_id,
    var.route_table_private_b_id
  ]
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  vpc_id            = var.vpc_main_id

  tags = {
    "Name" = "hv-vpp-${var.environment}-s3"
  }
}

resource "aws_vpc_endpoint" "ssm" {
  private_dns_enabled = true
  security_group_ids = [
    var.vpc_access_sg_id,
  ]
  service_name = "com.amazonaws.${var.region}.ssm"
  subnet_ids = [
    var.subnet_a_id,
    var.subnet_b_id
  ]
  vpc_endpoint_type = "Interface"
  vpc_id            = var.vpc_main_id

  tags = {
    "Name" = "hv-vpp-${var.environment}-ssm"
  }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  private_dns_enabled = true
  security_group_ids = [
    var.vpc_access_sg_id,
  ]
  service_name = "com.amazonaws.${var.region}.ssmmessages"
  subnet_ids = [
    var.subnet_a_id,
    var.subnet_b_id
  ]
  vpc_endpoint_type = "Interface"
  vpc_id            = var.vpc_main_id

  tags = {
    "Name" = "hv-vpp-${var.environment}-ssmmessages"
  }
}