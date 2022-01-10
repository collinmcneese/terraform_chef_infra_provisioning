terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }

  required_version = ">= 1.0.0"
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

data "aws_ami" "amazon-linux-2" {
  most_recent = true
  name_regex  = "^amzn2-ami-hvm-.*x86_64-gp2$"
  owners      = ["amazon"]
}

resource "aws_security_group" "amz_server_sg" {
  vpc_id      = var.aws_vpc_id
  description = "Security Group created by Terraform plan."
  tags        = var.aws_tags
}

resource "aws_security_group_rule" "internal_sg_traffic" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.amz_server_sg.id
  source_security_group_id = aws_security_group.amz_server_sg.id
}

resource "aws_security_group_rule" "ingress_ssh_rule" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.security_group_ingress_cidr
  security_group_id = aws_security_group.amz_server_sg.id
}

resource "aws_security_group_rule" "egress_rule" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.amz_server_sg.id
}
