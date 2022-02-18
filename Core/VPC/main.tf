variable "vpc_ip_block" {
  type = string
}

variable "nwave_ip_block" {
  type = string
}

variable "public_route_peering_ip_block" {
  type = string
}

variable "public_route_peering_connection_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "region" {
  type = string
}

locals {
  pub_subnet_cidr_a = {
    "ti" : cidrsubnet(var.nwave_ip_block, 1, 0),
    "uat" : cidrsubnet(var.nwave_ip_block, 1, 1),
    "prod" : cidrsubnet(var.nwave_ip_block, 1, 0)
  }
  pub_subnet_cidr_b = {
    "ti" : cidrsubnet(var.nwave_ip_block, 1, 1),
    "uat" : cidrsubnet(var.nwave_ip_block, 1, 0),
    "prod" : cidrsubnet(var.nwave_ip_block, 1, 1)
  }
  public_route_default = {
    cidr_block                 = "0.0.0.0/0"
    gateway_id                 = data.aws_vpn_gateway.main.id
    nat_gateway_id             = ""
    carrier_gateway_id         = ""
    destination_prefix_list_id = ""
    egress_only_gateway_id     = ""
    instance_id                = ""
    ipv6_cidr_block            = ""
    local_gateway_id           = ""
    network_interface_id       = ""
    transit_gateway_id         = ""
    vpc_endpoint_id            = ""
    vpc_peering_connection_id  = ""
  }
  public_route = var.public_route_peering_ip_block != "" ? [
    local.public_route_default,
    {
      carrier_gateway_id         = ""
      cidr_block                 = var.public_route_peering_ip_block
      destination_prefix_list_id = ""
      egress_only_gateway_id     = ""
      gateway_id                 = ""
      instance_id                = ""
      ipv6_cidr_block            = ""
      local_gateway_id           = ""
      nat_gateway_id             = ""
      network_interface_id       = ""
      transit_gateway_id         = ""
      vpc_endpoint_id            = ""
      vpc_peering_connection_id  = var.public_route_peering_connection_id
    }
  ] : [local.public_route_default]
}

resource "aws_vpc" "main" {
  cidr_block                     = var.vpc_ip_block
  instance_tenancy               = "default"
  enable_classiclink             = false
  enable_classiclink_dns_support = false
  enable_dns_hostnames           = true
  enable_dns_support             = true

  tags = {
    Name = "hydrovis-${var.environment}-vpc"
  }
}

# This is only created if the environment is not prod
resource "aws_vpc_ipv4_cidr_block_association" "public_cidr" {
  count      = var.environment != "prod" ? 1 : 0
  vpc_id     = aws_vpc.main.id
  cidr_block = var.nwave_ip_block
}

data "aws_vpn_gateway" "main" {
  tags = {
    Name = "hydrovis-${var.environment}-vgw"
  }
}

resource "aws_vpn_gateway_attachment" "main" {
  vpc_id         = aws_vpc.main.id
  vpn_gateway_id = data.aws_vpn_gateway.main.id
}

resource "aws_nat_gateway" "hv-pub-nat-gw-a" {
  connectivity_type = "private"
  subnet_id         = aws_subnet.hydrovis-sn-pub-1a.id
  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
}

resource "aws_nat_gateway" "hv-pub-nat-gw-b" {
  connectivity_type = "private"
  subnet_id         = aws_subnet.hydrovis-sn-pub-1b.id
  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
}

resource "aws_route_table" "private" {
  route = [
    {
      cidr_block                 = "0.0.0.0/0"
      nat_gateway_id             = aws_nat_gateway.hv-pub-nat-gw-a.id
      carrier_gateway_id         = ""
      destination_prefix_list_id = ""
      egress_only_gateway_id     = ""
      gateway_id                 = ""
      instance_id                = ""
      ipv6_cidr_block            = ""
      local_gateway_id           = ""
      network_interface_id       = ""
      transit_gateway_id         = ""
      vpc_endpoint_id            = ""
      vpc_peering_connection_id  = ""
    }
  ]
  vpc_id = aws_vpc.main.id
}

resource "aws_main_route_table_association" "main_private" {
  vpc_id         = aws_vpc.main.id
  route_table_id = aws_route_table.private.id
}

resource "aws_subnet" "hydrovis-sn-prv-data1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_ip_block, 4, 2)
  availability_zone = "${var.region}a"
  tags = {
    Name = "hydrovis-sn-prv-${var.environment}-data1a"
  }
  depends_on = [
    aws_main_route_table_association.main_private
  ]
}

resource "aws_subnet" "hydrovis-sn-prv-data1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_ip_block, 4, 5)
  availability_zone = "${var.region}b"
  tags = {
    Name = "hydrovis-sn-prv-${var.environment}-data1b"
  }
  depends_on = [
    aws_main_route_table_association.main_private
  ]
}

resource "aws_subnet" "hydrovis-sn-prv-app1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_ip_block, 4, 0)
  availability_zone = "${var.region}a"
  tags = {
    Name = "hydrovis-sn-prv-${var.environment}-app1a"
  }
  depends_on = [
    aws_main_route_table_association.main_private
  ]
}

resource "aws_subnet" "hydrovis-sn-prv-app1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_ip_block, 4, 1)
  availability_zone = "${var.region}b"
  tags = {
    Name = "hydrovis-sn-prv-${var.environment}-app1b"
  }
  depends_on = [
    aws_main_route_table_association.main_private
  ]
}

resource "aws_subnet" "hydrovis-sn-prv-web1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_ip_block, 4, 4)
  availability_zone = "${var.region}a"
  tags = {
    Name = "hydrovis-sn-prv-${var.environment}-web1a"
  }
  depends_on = [
    aws_main_route_table_association.main_private
  ]
}

resource "aws_subnet" "hydrovis-sn-prv-web1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_ip_block, 4, 3)
  availability_zone = "${var.region}b"
  tags = {
    Name = "hydrovis-sn-prv-${var.environment}-web1b"
  }
  depends_on = [
    aws_main_route_table_association.main_private
  ]
}



resource "aws_route_table" "public" {
  route = local.public_route
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "hydrovis-sn-pub-1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.pub_subnet_cidr_a[var.environment]
  availability_zone = "${var.region}a"
  tags = {
    Name = "hydrovis-sn-pub-${var.environment}-1a"
  }
}

resource "aws_subnet" "hydrovis-sn-pub-1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.pub_subnet_cidr_b[var.environment]
  availability_zone = "us-east-1b"
  tags = {
    Name = "hydrovis-sn-pub-${var.environment}-1b"
  }
}

resource "aws_route_table_association" "hydrovis-sn-pub-1a_public" {
  subnet_id      = aws_subnet.hydrovis-sn-pub-1a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_network_acl" "hydrovis-acl-default" {
  vpc_id = aws_vpc.main.id
  subnet_ids = [aws_subnet.hydrovis-sn-prv-data1a.id,
    aws_subnet.hydrovis-sn-prv-data1b.id,
    aws_subnet.hydrovis-sn-prv-app1a.id,
    aws_subnet.hydrovis-sn-prv-app1b.id,
    aws_subnet.hydrovis-sn-prv-web1a.id,
    aws_subnet.hydrovis-sn-prv-web1b.id,
    aws_subnet.hydrovis-sn-pub-1a.id,
  aws_subnet.hydrovis-sn-pub-1b.id]
  ingress {
    protocol   = "-1"
    rule_no    = "10"
    action     = "deny"
    cidr_block = "185.224.139.151/32"
    from_port  = 0
    to_port    = 0
  }
  egress {
    protocol   = "-1"
    rule_no    = "10"
    action     = "deny"
    cidr_block = "185.224.139.151/32"
    from_port  = 0
    to_port    = 0
  }
  ingress {
    protocol   = "-1"
    rule_no    = "11"
    action     = "deny"
    cidr_block = "45.83.193.150/32"
    from_port  = 0
    to_port    = 0
  }
  egress {
    protocol   = "-1"
    rule_no    = "11"
    action     = "deny"
    cidr_block = "45.83.193.150/32"
    from_port  = 0
    to_port    = 0
  }
  ingress {
    protocol   = "-1"
    rule_no    = "12"
    action     = "deny"
    cidr_block = "31.131.16.127/32"
    from_port  = 0
    to_port    = 0
  }
  egress {
    protocol   = "-1"
    rule_no    = "12"
    action     = "deny"
    cidr_block = "31.131.16.127/32"
    from_port  = 0
    to_port    = 0
  }
  ingress {
    protocol   = "-1"
    rule_no    = "13"
    action     = "deny"
    cidr_block = "195.54.160.149/32"
    from_port  = 0
    to_port    = 0
  }
  egress {
    protocol   = "-1"
    rule_no    = "13"
    action     = "deny"
    cidr_block = "195.54.160.149/32"
    from_port  = 0
    to_port    = 0
  }
  ingress {
    protocol   = "-1"
    rule_no    = "14"
    action     = "deny"
    cidr_block = "135.148.143.217/32"
    from_port  = 0
    to_port    = 0
  }
  egress {
    protocol   = "-1"
    rule_no    = "14"
    action     = "deny"
    cidr_block = "135.148.143.217/32"
    from_port  = 0
    to_port    = 0
  }
  ingress {
    protocol   = "-1"
    rule_no    = "15"
    action     = "deny"
    cidr_block = "159.223.5.30/32"
    from_port  = 0
    to_port    = 0
  }
  egress {
    protocol   = "-1"
    rule_no    = "15"
    action     = "deny"
    cidr_block = "159.223.5.30/32"
    from_port  = 0
    to_port    = 0
  }
  ingress {
    protocol   = "-1"
    rule_no    = "100"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
  egress {
    protocol   = "-1"
    rule_no    = "100"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    "Name" = "hydrovis-${var.environment}-acl-default"
  }
}


output "route_table_private" {
  value = aws_route_table.private
}

output "vpc_main" {
  value = aws_vpc.main
}

output "subnet_hydrovis-sn-prv-data1a" {
  value = aws_subnet.hydrovis-sn-prv-data1a
}

output "subnet_hydrovis-sn-prv-data1b" {
  value = aws_subnet.hydrovis-sn-prv-data1b
}

output "subnet_hydrovis-sn-prv-app1a" {
  value = aws_subnet.hydrovis-sn-prv-app1a
}

output "subnet_hydrovis-sn-prv-app1b" {
  value = aws_subnet.hydrovis-sn-prv-app1b
}

output "subnet_hydrovis-sn-prv-web1a" {
  value = aws_subnet.hydrovis-sn-prv-web1a
}

output "subnet_hydrovis-sn-prv-web1b" {
  value = aws_subnet.hydrovis-sn-prv-web1b
}

output "acl_hydrovis-acl" {
  value = aws_network_acl.hydrovis-acl-default
}
