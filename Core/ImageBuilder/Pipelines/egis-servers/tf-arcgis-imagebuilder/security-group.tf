variable "vpc_main_cidr_block" {
  type = string
}

variable "vpc_main_id" {
  type = string
}

resource "aws_security_group" "hydrovis-ec2-egis-image-builder-sg" {
  description = "Allow inbound/outbound traffic to Image Builder"
  vpc_id = var.vpc_main_id
  name = "hv-ec2-egis-image-builder-sg"
  tags = {
    "Name" = "hv-ec2-egis-image-builder-sg"
  }
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
}

output "id" {
  value = aws_security_group.hydrovis-ec2-egis-image-builder-sg.id
}
