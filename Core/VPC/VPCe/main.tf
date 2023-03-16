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

variable "ssm-session-manager-sg_id" {
  type = string
}

variable "opensearch-access_id" {
  type = string
}


# This is here because dev/ti use a different route table than the main RT for the private subnets
# data "aws_route_table" "other" {
#   count = var.environment == "ti" ? 1 : 0

#   subnet_id = var.subnet_a_id
# }


resource "aws_vpc_endpoint" "ec2messages" {
  private_dns_enabled = true
  security_group_ids = [
    var.ssm-session-manager-sg_id,
  ]
  service_name = "com.amazonaws.${var.region}.ec2messages"
  subnet_ids = [
    var.subnet_a_id,
    var.subnet_b_id
  ]
  vpc_endpoint_type = "Interface"
  vpc_id            = var.vpc_main_id
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
}

resource "aws_vpc_endpoint" "ssm" {
  private_dns_enabled = true
  security_group_ids = [
    var.ssm-session-manager-sg_id,
  ]
  service_name = "com.amazonaws.${var.region}.ssm"
  subnet_ids = [
    var.subnet_a_id,
    var.subnet_b_id
  ]
  vpc_endpoint_type = "Interface"
  vpc_id            = var.vpc_main_id
}

resource "aws_vpc_endpoint" "ssmmessages" {
  private_dns_enabled = true
  security_group_ids = [
    var.ssm-session-manager-sg_id,
  ]
  service_name = "com.amazonaws.${var.region}.ssmmessages"
  subnet_ids = [
    var.subnet_a_id,
    var.subnet_b_id
  ]
  vpc_endpoint_type = "Interface"
  vpc_id            = var.vpc_main_id
}

resource "aws_vpc_endpoint" "cloudwatch_logs" {
  private_dns_enabled = true
  security_group_ids = [
    var.opensearch-access_id,
  ]
  service_name = "com.amazonaws.${var.region}.logs"
  subnet_ids = [
    var.subnet_a_id,
    var.subnet_b_id
  ]
  vpc_endpoint_type = "Interface"
  vpc_id            = var.vpc_main_id
}