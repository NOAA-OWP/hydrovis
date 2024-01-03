variable "environment" {
  type = string
}

variable "db_viz_redshift_security_groups" {
  type = list(any)
}

variable "subnet-a" {
  type = string
}

variable "subnet-b" {
  type = string
}

variable "db_viz_redshift_master_secret_string" {
  type = string
}

variable "db_viz_redshift_user_secret_string" {
  type = string
}

variable "viz_redshift_db_name" {
  type = string
}

variable "role_viz_redshift_arn" {
  type = string
}

variable "private_route_53_zone" {
  type = object({
    name     = string
    zone_id  = string
  })
}

resource "aws_redshift_subnet_group" "viz_redshift_subnet_group" {
  name       = "hv-vpp-${var.environment}-viz-data-warehouse-subnets"
  subnet_ids = [var.subnet-a, var.subnet-b]
  tags = {
    Name = "Viz Redshift Data Warehouse Subnet Group"
  }
}

resource "aws_redshift_cluster" "viz_redshift_data_warehouse" {
  cluster_identifier        = "hv-vpp-${var.environment}-viz-data-warehouse"
  database_name             = var.viz_redshift_db_name
  master_username           = jsondecode(var.db_viz_redshift_master_secret_string)["username"]
  master_password           = jsondecode(var.db_viz_redshift_master_secret_string)["password"]
  node_type                 = "dc2.large"
  cluster_type              = "single-node"
  iam_roles                 = [var.role_viz_redshift_arn]
  vpc_security_group_ids    = var.db_viz_redshift_security_groups
  cluster_subnet_group_name = aws_redshift_subnet_group.viz_redshift_subnet_group.name
}

resource "aws_route53_record" "viz_redshift_data_warehouse" {
  zone_id = var.private_route_53_zone.zone_id
  name    = "redshift-viz.${var.private_route_53_zone.name}"
  type    = "CNAME"
  ttl     = 300
  records = [aws_redshift_cluster.viz_redshift_data_warehouse.dns_name]
}

output "dns_name" {
  value = aws_route53_record.viz_redshift_data_warehouse.name
}

output "port" {
  value = aws_redshift_cluster.viz_redshift_data_warehouse.port
}