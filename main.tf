terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}

# DATA - AMAZON LINUX 2023 AMI

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# VPC

resource "aws_vpc" "VPC01" {
  cidr_block           = "192.168.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "VPC01"
  }
}

# INTERNET GATEWAY

resource "aws_internet_gateway" "VPC01-IGW" {
  vpc_id = aws_vpc.VPC01.id

  tags = {
    Name = "VPC01-IGW"
  }
}

# PUBLIC SUBNET

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.VPC01.id
  cidr_block              = "192.168.1.0/24"
  availability_zone       = "eu-west-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "Public-Subnet"
  }
}

# PRIVATE SUBNET

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.VPC01.id
  cidr_block        = "192.168.2.0/24"
  availability_zone = "eu-west-1a"

  tags = {
    Name = "Private-Subnet"
  }
}

# PUBLIC ROUTE TABLE

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.VPC01.id

  tags = {
    Name = "Public-Route-Table"
  }
}

# PUBLIC ROUTE TO INTERNET GATEWAY

resource "aws_route" "public_internet_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.VPC01-IGW.id
}

# PUBLIC SUBNET ROUTE TABLE ASSOCIATION

resource "aws_route_table_association" "public_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# PRIVATE ROUTE TABLE

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.VPC01.id

  tags = {
    Name = "Private-Route-Table"
  }
}

# PRIVATE ROUTE THROUGH NAT INSTANCE

resource "aws_route" "private_nat_route" {
  route_table_id         = aws_route_table.private_rt.id
  destination_cidr_block = "0.0.0.0/0"
  instance_id             = aws_instance.nat.id
}

# PRIVATE SUBNET ROUTE TABLE ASSOCIATION

resource "aws_route_table_association" "private_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

# NAT INSTANCE SECURITY GROUP

resource "aws_security_group" "nat_sg" {
  name        = "NAT-Instance-SG"
  description = "Security group for NAT instance"
  vpc_id      = aws_vpc.VPC01.id

  # all traffic inbound traffic
  ingress {
    description = "All traffic"
    from_port   = 0
    to_port     = 65535
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  # Allow all outbound traffic
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "NAT-Instance-SG"
  }
}

# PRIVATE EC2 SECURITY GROUP

resource "aws_security_group" "private_sg" {
  name        = "Private-EC2-SG"
  description = "Security group for private EC2"
  vpc_id      = aws_vpc.VPC01.id

  # SSH from NAT/Public network for lab testing
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["192.168.0.0/16"]
  }

  # Allow HTTP outbound
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Private-EC2-SG"
  }
}

# KEY PAIR

resource "aws_key_pair" "terraform_key" {
  key_name = "terraform-nat-key"

  public_key = "YOUR_PUBLIC_SSH_KEY_HERE"
}

# NAT INSTANCE

resource "aws_instance" "nat" {
  ami           = data.aws_ssm_parameter.al2023_ami.value
  instance_type = "t3.micro"

  subnet_id = aws_subnet.public_subnet.id

  key_name = aws_key_pair.terraform_key.key_name

  vpc_security_group_ids = [
    aws_security_group.nat_sg.id
  ]

  # VERY IMPORTANT
  # NAT instance must forward traffic for other instances
  source_dest_check = false

  user_data = <<-EOF
    #!/bin/bash

    # Enable IPv4 forwarding
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/custom-ip-forwarding.conf

    sysctl -p /etc/sysctl.d/custom-ip-forwarding.conf

    # Install iptables
    dnf install -y iptables-services

    # Enable iptables service
    systemctl enable iptables
    systemctl start iptables

    # Automatically detect primary network interface
    INTERFACE=$(ip route | awk '/default/ {print $5; exit}')

    # Enable NAT / MASQUERADE
    /sbin/iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE

    # Allow forwarding
    /sbin/iptables -F FORWARD

    # Save iptables configuration
    service iptables save
  EOF

  tags = {
    Name = "NAT-Instance"
  }
}

# ELASTIC IP FOR NAT INSTANCE

resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "NAT-Instance-EIP"
  }
}

# ASSOCIATE EIP WITH NAT INSTANCE

resource "aws_eip_association" "nat_eip_association" {
  allocation_id = aws_eip.nat_eip.id
  instance_id   = aws_instance.nat.id
}

# PRIVATE EC2

resource "aws_instance" "private_ec2" {
  ami           = data.aws_ssm_parameter.al2023_ami.value
  instance_type = "t3.micro"

  subnet_id = aws_subnet.private_subnet.id

  key_name = aws_key_pair.terraform_key.key_name

  vpc_security_group_ids = [
    aws_security_group.private_sg.id
  ]

  # No public IP
  associate_public_ip_address = false

  tags = {
    Name = "Private-EC2"
  }
}

# OUTPUTS

output "vpc_id" {
  value = aws_vpc.VPC01.id
}

output "public_subnet_id" {
  value = aws_subnet.public_subnet.id
}

output "private_subnet_id" {
  value = aws_subnet.private_subnet.id
}

output "nat_instance_id" {
  value = aws_instance.nat.id
}

output "nat_private_ip" {
  value = aws_instance.nat.private_ip
}

output "nat_public_ip" {
  value = aws_eip.nat_eip.public_ip
}

output "private_ec2_id" {
  value = aws_instance.private_ec2.id
}

output "private_ec2_private_ip" {
  value = aws_instance.private_ec2.private_ip
}