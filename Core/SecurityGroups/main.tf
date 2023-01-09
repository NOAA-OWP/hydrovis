variable "environment" {
  type = string
}

variable "nwave_ip_block" {
  type = string
}

variable "vpc_ip_block" {
  type = string
}

variable "nwc_ip_block" {
  type = string
}

variable "vpc_main_id" {
  type = string
}

variable "vpc_main_cidr_block" {
  type = string
}
variable "subnet_hydrovis-sn-prv-data1a_cidr_block" {
  type = string
}

variable "subnet_hydrovis-sn-prv-data1b_cidr_block" {
  type = string
}

variable "public_route_peering_ip_block" {
  type = string
}


locals {
  hydrovis-RDS_ingress_default = [
    {
      cidr_blocks = [
        var.vpc_ip_block,
      ]
      description      = ""
      from_port        = 22
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 22
    },
    {
      cidr_blocks = [
        var.vpc_ip_block,
      ]
      description      = ""
      from_port        = 5432
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 5432
    },
  ]

  hydrovis-RDS_ingress = var.public_route_peering_ip_block != "" ? concat(
    local.hydrovis-RDS_ingress_default,
    [
      {
        cidr_blocks      = [
            var.public_route_peering_ip_block,
          ]
        description      = "Peering from Dev"
        from_port        = 5432
        ipv6_cidr_blocks = []
        prefix_list_ids  = []
        protocol         = "tcp"
        security_groups  = []
        self             = false
        to_port          = 5432
      },
    ]
  ) : local.hydrovis-RDS_ingress_default
}


resource "aws_security_group" "es-sg" {
  description = "Allow inbound traffic to ElasticSearch from VPC CIDR"
  egress = [
    {
      cidr_blocks = [
        "0.0.0.0/0",
      ]
      description      = ""
      from_port        = 0
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "-1"
      security_groups  = []
      self             = false
      to_port          = 0
    },
  ]
  ingress = [
    {
      cidr_blocks = [
        var.vpc_main_cidr_block,
      ]
      description      = ""
      from_port        = 443
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 443
    },
  ]
  name = "es-sg"
  tags = {
    "Name" = "es-sg"
  }
  vpc_id = var.vpc_main_id
}

resource "aws_security_group" "hv-allow-NWC-access" {
  description = "Allow NWC vpn users access to Portal"
  ingress = [
    {
      cidr_blocks = [
        "0.0.0.0/0",
        var.nwc_ip_block,
      ]
      description      = ""
      from_port        = 443
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 443
    },
  ]
  name = "hv-${var.environment}-allow-NWC-access"
  tags = {
    "Name" = "hv-${var.environment}-internet-443-from-NWC"
  }
  vpc_id = var.vpc_main_id
}

resource "aws_security_group" "hv-rabbitmq" {
  description = "Allows rabbit MQ connection and dashboard"
  egress = [
    {
      cidr_blocks = [
        "0.0.0.0/0",
      ]
      description      = ""
      from_port        = 0
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "-1"
      security_groups  = []
      self             = false
      to_port          = 0
    },
  ]
  ingress = [
    {
      cidr_blocks = [
        var.vpc_ip_block,
      ]
      description      = ""
      from_port        = 443
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 443
    },
    {
      cidr_blocks = [
        var.vpc_ip_block,
      ]
      description      = ""
      from_port        = 5671
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 5671
    },
    {
      cidr_blocks = [
        var.subnet_hydrovis-sn-prv-data1b_cidr_block,
      ]
      description      = "Access from subnet hydrovis-sn-prv-${var.environment}-data1b"
      from_port        = 443
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 443
    },
    {
      cidr_blocks = [
        var.subnet_hydrovis-sn-prv-data1b_cidr_block,
      ]
      description      = "Access from subnet hydrovis-sn-prv-${var.environment}-data1b"
      from_port        = 5671
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 5671
    },
    {
      cidr_blocks = [
        var.subnet_hydrovis-sn-prv-data1a_cidr_block,
      ]
      description      = "Access from subnet hydrovis-sn-prv-${var.environment}-data1a"
      from_port        = 443
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 443
    },
    {
      cidr_blocks = [
        var.subnet_hydrovis-sn-prv-data1a_cidr_block,
      ]
      description      = "Access from subnet hydrovis-sn-prv-${var.environment}-data1a"
      from_port        = 5671
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 5671
    },
  ]
  name = "hv-${var.environment}-rabbitmq"
  tags = {
    "vpc"  = "${var.environment}"
    "Name" = "hv-${var.environment}-rabbitmq"
  }
  vpc_id = var.vpc_main_id
}

resource "aws_security_group" "hv-test-loadbalancer-sg" {
  description = "Security group for testing ALB access from internet"
  ingress = [
    {
      cidr_blocks = [
        "0.0.0.0/0",
      ]
      description = ""
      from_port   = 443
      ipv6_cidr_blocks = [
        "::/0",
      ]
      prefix_list_ids = []
      protocol        = "tcp"
      security_groups = []
      self            = false
      to_port         = 443
    },
  ]
  name = "hv-${var.environment}-test-loadbalancer-sg"
  tags = {
    "Name" = "hv-${var.environment}-test-loadbalancer-sg"
  }
  vpc_id = var.vpc_main_id
}

resource "aws_security_group" "hydrovis-RDS" {
  description = "${upper(var.environment)} RDS access"
  egress = [
    {
      cidr_blocks = [
        "0.0.0.0/0",
      ]
      description      = ""
      from_port        = 0
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "-1"
      security_groups  = []
      self             = false
      to_port          = 0
    },
  ]
  ingress = local.hydrovis-RDS_ingress
  name = "hydrovis-${upper(var.environment)}-RDS"
  tags = {
    "vpc"  = "${var.environment}"
    "Name" = "hydrovis-${upper(var.environment)}-RDS"
  }
  vpc_id = var.vpc_main_id
}

resource "aws_security_group" "hydrovis-nat-sg" {
  description = "Security group for NAT instance for hydrovis ${upper(var.environment)} VPC"
  egress = [
    {
      cidr_blocks = [
        "0.0.0.0/0",
      ]
      description      = ""
      from_port        = 0
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "-1"
      security_groups  = []
      self             = false
      to_port          = 0
    },
  ]
  ingress = [
    {
      cidr_blocks = [
        var.vpc_main_cidr_block,
      ]
      description      = "Allow all inbound traffic from private subnets"
      from_port        = 0
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "-1"
      security_groups  = []
      self             = false
      to_port          = 0
    },
  ]
  name = "hydrovis-${var.environment}-nat-sg"
  tags = {
    "Name" = "hydrovis-${var.environment}-nat-sg"
  }
  vpc_id = var.vpc_main_id
}

resource "aws_security_group" "ssm-session-manager-sg" {
  description = "allow access to VPC endpoints"
  egress = [
    {
      cidr_blocks = [
        "0.0.0.0/0",
      ]
      description      = ""
      from_port        = 0
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "-1"
      security_groups  = []
      self             = false
      to_port          = 0
    },
  ]
  ingress = [
    {
      cidr_blocks = [
        var.vpc_main_cidr_block,
        var.nwave_ip_block,
      ]
      description      = ""
      from_port        = 0
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "-1"
      security_groups  = []
      self             = false
      to_port          = 0
    },
  ]

  lifecycle {
    ignore_changes = [
      ingress
    ]
  }
  
  name = "ssm-session-manager-sg"
  tags = {
    "Name" = "ssm-session-manager-sg"
  }
  vpc_id = var.vpc_main_id
}

resource "aws_security_group" "egis-overlord" {
  description = "Allow inbound traffic to eGIS environment"
  egress = [
    {
      cidr_blocks = [
        "0.0.0.0/0",
      ]
      description      = ""
      from_port        = 0
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "-1"
      security_groups  = []
      self             = false
      to_port          = 0
    },
  ]
  ingress = [
    {
      cidr_blocks = [
        var.vpc_main_cidr_block,
      ]
      description      = "Session Manager Access"
      from_port        = 0
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = -1
      security_groups  = []
      self             = false
      to_port          = 0
    },
    {
      cidr_blocks = [
        var.vpc_main_cidr_block,
      ]
      description      = "Web Tier Access"
      from_port        = 443
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 443
    },
    {
      cidr_blocks = [
        var.vpc_main_cidr_block,
      ]
      description      = "ArcGIS Server Private Access gis, img, gp"
      from_port        = 6443
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 6443
    },
    {
      cidr_blocks = [
        var.vpc_main_cidr_block,
      ]
      description      = "Portal Private Access"
      from_port        = 7443
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 7443
    },
    {
      cidr_blocks = [
        var.vpc_main_cidr_block,
      ]
      description      = "PostGres Private Access"
      from_port        = 5432
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 5432
    },
    {
      cidr_blocks = [
        var.vpc_main_cidr_block,
      ]
      description      = "ArcGIS DataStore Private Access"
      from_port        = 2443
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 2443
    },
    {
      cidr_blocks = [
        var.vpc_main_cidr_block,
      ]
      description      = "Data Sharing"
      from_port        = 139
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 139
    },
    {
      cidr_blocks = [
        var.vpc_main_cidr_block,
      ]
      description      = "RDP Access"
      from_port        = 3389
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 3389
    },
    {
      cidr_blocks = [
        var.vpc_main_cidr_block,
      ]
      description      = "Data Sharing"
      from_port        = 445
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 445
    },
  ]

  lifecycle {
    ignore_changes = [
      ingress
    ]
  }
  
  name = "hv-${var.environment == "prod" ? "prd" : var.environment}-egis-ptl-gis-img-gp"
  tags = {
    "Name" = "hv-${var.environment == "prod" ? "prd" : var.environment}-egis-ptl-gis-img-gp"
  }
  vpc_id = var.vpc_main_id
}

output "egis-overlord" {
  value = aws_security_group.egis-overlord
}

output "es-sg" {
  value = aws_security_group.es-sg
}

output "hv-allow-NWC-access" {
  value = aws_security_group.hv-allow-NWC-access
}

output "hv-rabbitmq" {
  value = aws_security_group.hv-rabbitmq
}

output "hv-test-loadbalancer-sg" {
  value = aws_security_group.hv-test-loadbalancer-sg
}

output "hydrovis-RDS" {
  value = aws_security_group.hydrovis-RDS
}

output "hydrovis-nat-sg" {
  value = aws_security_group.hydrovis-nat-sg
}

output "ssm-session-manager-sg" {
  value = aws_security_group.ssm-session-manager-sg
}
