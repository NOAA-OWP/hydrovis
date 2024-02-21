variable "environment" {
  type = string
}

variable "account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_ip_block" {
  type = string
}

variable "nwave_ip_block" {
  type = string
}

variable "transit_gateway_id" {
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
}


# VPC
resource "aws_vpc" "main" {
  cidr_block                     = var.vpc_ip_block
  instance_tenancy               = "default"
  enable_dns_hostnames           = true
  enable_dns_support             = true

  tags = {
    Name = "hv-vpp-${var.environment}-vpc"
  }
}

resource "aws_vpc_ipv4_cidr_block_association" "public_cidr" {
  vpc_id     = aws_vpc.main.id
  cidr_block = var.nwave_ip_block
}


# NAT Gateways
resource "aws_nat_gateway" "a" {
  connectivity_type = "private"
  subnet_id         = aws_subnet.public_a.id

  tags = {
    Name = "hv-vpp-${var.environment}-nat-gw-a"
  }
}

resource "aws_nat_gateway" "b" {
  connectivity_type = "private"
  subnet_id         = aws_subnet.public_b.id

  tags = {
    Name = "hv-vpp-${var.environment}-nat-gw-b"
  }
}


# Private Subnets
resource "aws_subnet" "vpp_private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_ip_block, 2, 2)
  availability_zone = "${var.region}a"
  tags = {
    Name = "hv-vpp-${var.environment}-prv-sn-a"
  }
}

resource "aws_subnet" "vpp_private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_ip_block, 2, 3)
  availability_zone = "${var.region}b"
  tags = {
    Name = "hv-vpp-${var.environment}-prv-sn-b"
  }
}

resource "aws_subnet" "egis_private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_ip_block, 4, 4)
  availability_zone = "${var.region}a"
  tags = {
    Name = "hv-vpp-egis-${var.environment}-prv-sn-a"
  }
}

resource "aws_subnet" "egis_private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_ip_block, 4, 3)
  availability_zone = "${var.region}b"
  tags = {
    Name = "hv-vpp-egis-${var.environment}-prv-sn-b"
  }
}


# Private Route Tables
resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.a.id
  }

  tags = {
    Name = "hv-vpp-${var.environment}-prv-rt-a"
  }
}

resource "aws_route_table" "private_b" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.b.id
  }

  tags = {
    Name = "hv-vpp-${var.environment}-prv-rt-b"
  }
}


# Private Subnet to Private Route Table Associations
resource "aws_route_table_association" "vpp_private_a_private" {
  subnet_id      = aws_subnet.vpp_private_a.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "vpp_private_b_private" {
  subnet_id      = aws_subnet.vpp_private_b.id
  route_table_id = aws_route_table.private_b.id
}

resource "aws_route_table_association" "egis_private_a_private" {
  subnet_id      = aws_subnet.egis_private_a.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "egis_private_b_private" {
  subnet_id      = aws_subnet.egis_private_b.id
  route_table_id = aws_route_table.private_b.id
}


# Public Subnets
resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.pub_subnet_cidr_a[var.environment]
  availability_zone = "${var.region}a"

  tags = {
    Name = "hv-vpp-${var.environment}-pub-sn-a"
  }

  depends_on = [
    aws_vpc_ipv4_cidr_block_association.public_cidr
  ]
}

resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.pub_subnet_cidr_b[var.environment]
  availability_zone = "${var.region}b"

  tags = {
    Name = "hv-vpp-${var.environment}-pub-sn-b"
  }

  depends_on = [
    aws_vpc_ipv4_cidr_block_association.public_cidr
  ]
}


# Transit Gateway Attachment
resource "aws_ec2_transit_gateway_vpc_attachment" "main" {
  subnet_ids         = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  transit_gateway_id = var.transit_gateway_id
  vpc_id             = aws_vpc.main.id
  dns_support        = "disable"

  tags = {
    Name = "nws-diss-hydrovis-${var.environment}-${var.account_id}-hydrovis-${var.environment}-vpc-attach-01"
  }
}


# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block         = "0.0.0.0/0"
    transit_gateway_id = var.transit_gateway_id
  }

  tags = {
    Name = "hv-vpp-${var.environment}-pub-rt"
  }

  depends_on = [
    aws_ec2_transit_gateway_vpc_attachment.main
  ]
}


# Public Subnet to Public Route Table Associations
resource "aws_route_table_association" "public_a_public" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id

  depends_on = [
    aws_ec2_transit_gateway_vpc_attachment.main
  ]
}

resource "aws_route_table_association" "public_b_public" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id

  depends_on = [
    aws_ec2_transit_gateway_vpc_attachment.main
  ]
}


# VPC ACL
resource "aws_network_acl" "default" {
  vpc_id = aws_vpc.main.id
  subnet_ids = [
    aws_subnet.vpp_private_a.id,
    aws_subnet.vpp_private_b.id,
    aws_subnet.egis_private_a.id,
    aws_subnet.egis_private_b.id,
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]
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
    "Name" = "hv-vpp-${var.environment}-acl-default"
  }
}


output "vpc_main" {
  value = aws_vpc.main
}

output "route_table_private_a" {
  value = aws_route_table.private_a
}

output "route_table_private_b" {
  value = aws_route_table.private_b
}

output "subnet_private_a" {
  value = aws_subnet.vpp_private_a
}

output "subnet_private_b" {
  value = aws_subnet.vpp_private_b
}