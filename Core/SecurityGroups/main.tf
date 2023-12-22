variable "environment" {
  type = string
}

variable "nwave_ip_block" {
  type = string
}

variable "vpc_main_id" {
  type = string
}

variable "vpc_main_cidr_block" {
  type = string
}


resource "aws_security_group" "rabbitmq" {
  name = "hv-vpp-${var.environment}-rabbitmq"
  description = "Allows rabbit MQ connection and dashboard"
  vpc_id = var.vpc_main_id

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
    {
      cidr_blocks = [
        var.vpc_main_cidr_block,
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
  ]
  
  tags = {
    "Name" = "hv-vpp-${var.environment}-rabbitmq"
  }
}

resource "aws_security_group" "rds" {
  name = "hv-vpp-${var.environment}-rds"
  description = "RDS access"
  vpc_id = var.vpc_main_id

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
        var.vpc_main_cidr_block,
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
  
  tags = {
    "Name" = "hv-vpp-${var.environment}-rds"
  }
}

resource "aws_security_group" "redshift" {
  name = "hv-vpp-${var.environment}-redshift"
  description = "Redshift access"
  vpc_id = var.vpc_main_id

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
      from_port        = 5439
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 22
    }
  ]
  
  tags = {
    "Name" = "hv-vpp-${var.environment}-redshift"
  }
}

resource "aws_security_group" "vpc_access" {
  name = "ssm-session-manager-sg"
  description = "allow access to VPC endpoints"
  vpc_id = var.vpc_main_id

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
  
  
  tags = {
    "Name" = "hv-vpp-${var.environment}-vpc-access"
  }
}

resource "aws_security_group" "egis_overlord" {
  name = "hv-${var.environment == "prod" ? "prd" : var.environment}-egis-ptl-gis-img-gp"
  description = "Allow inbound traffic to eGIS environment"
  vpc_id = var.vpc_main_id
  
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
  
  tags = {
    "Name" = "hv-${var.environment == "prod" ? "prd" : var.environment}-egis-ptl-gis-img-gp"
  }
}

output "rabbitmq" {
  value = aws_security_group.rabbitmq
}

output "rds" {
  value = aws_security_group.rds
}

output "redshift" {
  value = aws_security_group.redshift
}

output "vpc_access" {
  value = aws_security_group.vpc_access
}

output "egis_overlord" {
  value = aws_security_group.egis_overlord
}