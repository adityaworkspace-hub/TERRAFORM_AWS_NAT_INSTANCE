terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "eu-west-1"
}

# Create a VPC
resource "aws_vpc" "VPC-01" {
  cidr_block       = "192.168.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "VPC-01"
  }
}

# Create & attach the IGW
resource "aws_internet_gateway" "VPC01-IGW" {
  vpc_id = aws_vpc.VPC-01.id

  tags = {
    Name = "VPC01-IGW"
  }
}

# Create a Public Subnet
resource "aws_subnet" "VPC01-Public-SN" {
  vpc_id     = aws_vpc.VPC-01.id
  cidr_block = "192.168.1.0/24"

  tags = {
    Name = "VPC01-Public-SN"
  }
}

# Create a Private Subnet
resource "aws_subnet" "VPC01-Private-SN" {
  vpc_id     = aws_vpc.VPC-01.id
  cidr_block = "192.168.3.0/24"

  tags = {
    Name = "VPC01-Private-SN"
  }
}

# Create a Public Route Table
resource "aws_route_table" "VPC01-Public-RT" {
  vpc_id = aws_vpc.VPC-01.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.VPC01-IGW.id
  }

  tags = {
    Name = "VPC01-Public-RT"
  }
}

resource "aws_route_table_association" "VPC01-Public-RT-Association" {
  subnet_id      = aws_subnet.VPC01-Public-SN.id
  route_table_id = aws_route_table.VPC01-Public-RT.id
}

# Create a EIP
resource "aws_eip" "NAT-EIP" {
  domain   = "vpc"
}


# Create a Private Route Table
resource "aws_route_table" "VPC01-Private-RT" {
  vpc_id = aws_vpc.VPC-01.id

  route {
    cidr_block = "0.0.0.0/0"
     network_interface_id   = aws_instance.VPC01-NATEC2.primary_network_interface_id
  }

  tags = {
    Name = "VPC01-Private-RT"
  }
}

resource "aws_route_table_association" "VPC01-Private-RT-Association" {
  subnet_id      = aws_subnet.VPC01-Private-SN.id
  route_table_id = aws_route_table.VPC01-Private-RT.id
}

#Create NAT INSTANCE
#----------------------------------------------------------------------------------------------------------------------------------------------------------

# Create a Security Group
resource "aws_security_group" "VPC01-NAT-NSG" {
  name        = "VPC01-NAT-NSG"
  description = "Allow all inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.VPC-01.id

  tags = {
    Name = "VPC01-NAT-NSG"
  }
}

#Create keypair
resource "aws_key_pair" "NAT_Server_Key" {
  key_name   = "NAT_Server_Key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQD3F6tyPEFEzV0LX3X8BsXdMsQz1x2cEikKDEY0aIj41qgxMCP/iteneqXSIFZBp5vizPvaoIR3Um9xK7PGoW8giupGn+EPuxIA4cDM4vzOqOkiMPhz5XK0whEjkVzTo4+S0puvDZuwIsdiW9mxhJc7tgBNL0cYlWSYVkz4G/fslNfRPW5mYAM49f4fhtxPb5ok4Q2Lg9dPKVHO/Bgeu5woMc7RY0p1ej6D4CKFE6lymSDJpW0YHX/wqE9+cfEauh7xZcG0q9t2ta6F6fmX0agvpFyZo8aFbXeUBr7osSCJNgvavWbM/06niWrOvYX2xwWdhXmXSrbX8ZbabVohBK41 email@example.com"
}

#ingress rule
resource "aws_vpc_security_group_ingress_rule" "allow_all_traffic_NAT" {
  security_group_id = aws_security_group.VPC01-NAT-NSG.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 0
  ip_protocol       = "-1"
  to_port           = 0
}

#egress rule
resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_NAT" {
  security_group_id = aws_security_group.VPC01-NAT-NSG.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_eip_association" "NAT-EIP" {
  allocation_id = aws_eip.NAT-EIP.id
  instance_id   = aws_instance.VPC01-NATEC2.id
}

resource "aws_instance" "VPC01-NATEC2" {
  ami           = "ami-0b3ba1acb76a70451"
  instance_type = "t3.micro"
  key_name      = "NAT_Server_Key"
  subnet_id     = aws_subnet.VPC01-Public-SN.id
  vpc_security_group_ids  = [aws_security_group.VPC01-NAT-NSG.id]
  user_data = file("/root/TERRAFORM_AWS_NAT_INSTANCE/nat_config.sh")
  source_dest_check = false

  tags = {
    Name = "VPC01-NATEC2"
  }
}


                                     #Creation of public server and private server

# ----------------------------------------------------------------------------------------------------------------------------------------------------------#


# Create a Security Group
resource "aws_security_group" "VPC01-VM-NSG" {
  name        = "VPC01-VM-NSG"
  description = "Allow SSH inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.VPC-01.id

  tags = {
    Name = "VPC01-VM-NSG"
  }
}

#Create keypair
resource "aws_key_pair" "Terraform_Server_Key" {
  key_name   = "Terraform_Server_Key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQD3F6tyPEFEzV0LX3X8BsXdMsQz1x2cEikKDEY0aIj41qgxMCP/iteneqXSIFZBp5vizPvaoIR3Um9xK7PGoW8giupGn+EPuxIA4cDM4vzOqOkiMPhz5XK0whEjkVzTo4+S0puvDZuwIsdiW9mxhJc7tgBNL0cYlWSYVkz4G/fslNfRPW5mYAM49f4fhtxPb5ok4Q2Lg9dPKVHO/Bgeu5woMc7RY0p1ej6D4CKFE6lymSDJpW0YHX/wqE9+cfEauh7xZcG0q9t2ta6F6fmX0agvpFyZo8aFbXeUBr7osSCJNgvavWbM/06niWrOvYX2xwWdhXmXSrbX8ZbabVohBK41 email@example.com"
}



resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
  security_group_id = aws_security_group.VPC01-VM-NSG.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.VPC01-VM-NSG.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

# Create a Public Instance
resource "aws_instance" "VPC01-Public-VM" {
  ami           = "ami-0b3ba1acb76a70451"
  instance_type = "t3.micro"
  key_name      = "Terraform_Server_Key"
  subnet_id     = aws_subnet.VPC01-Public-SN.id
  vpc_security_group_ids  = [aws_security_group.VPC01-VM-NSG.id]
  associate_public_ip_address 	=  true

  tags = {
    Name = "VPC01-Public-VM"
  }
}

# Create a Private Instance
resource "aws_instance" "VPC01-Private-VM" {
  ami           = "ami-0b3ba1acb76a70451"
  instance_type = "t3.micro"
  key_name      = "Terraform_Server_Key"
  subnet_id     = aws_subnet.VPC01-Private-SN.id
  vpc_security_group_ids  = [aws_security_group.VPC01-VM-NSG.id]
  associate_public_ip_address 	=  false
  tags = {
    Name = "VPC01-Private-VM"
  }
}