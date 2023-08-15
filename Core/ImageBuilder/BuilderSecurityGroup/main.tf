variable "vpc_main_cidr_block" {
  type = string
}

variable "vpc_main_id" {
  type = string
}

resource "aws_security_group" "hydrovis" {
  description = "Allow inbound traffic to Image Builder from VPC CIDR"
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
  name = "hv-image-builder-sg"
  tags = {
    "Name" = "hv-image-builder-sg"
  }
  vpc_id = var.vpc_main_id
}

output "id" {
  value = aws_security_group.hydrovis.id
}