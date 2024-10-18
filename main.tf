terraform {
  required_providers {
    aws = {
        source = "hashicorp/aws",
        version = "~> 5.5"
    }
    tls = {
      source = "hashicorp/tls"
      version = "4.0.4"
    }
    ansible = {
      source = "ansible/ansible"
      version = "1.3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"  # Altere para a região desejada
}

resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"  # Altere conforme necessário
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_route_table_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_security_group" "server_sg" {
  vpc_id = aws_vpc.main_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks =  ["45.164.77.0/24"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks =  ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks =  ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks =  ["0.0.0.0/0"]
  }
}

resource "tls_private_key" "private_key" {
  
  algorithm = "RSA"
  rsa_bits  = 4096

  provisioner "local-exec" {
    command = "echo '${self.public_key_pem}' > ./main-public-key.pem"
  }
}

resource "aws_key_pair" "key_pair" {
  key_name = var.keypair_name
  public_key = tls_private_key.private_key.public_key_openssh

  provisioner "local-exec" {
    command = "echo '${tls_private_key.private_key.private_key_pem}' > ./main-private-key.pem"
  }
  
}


resource "aws_instance" "main_server" {
  ami                    = "ami-0e86e20dae9224db8"
  instance_type         = "t3.medium"
  key_name              = aws_key_pair.key_pair.key_name
  associate_public_ip_address = true
  subnet_id             = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.server_sg.id]

  root_block_device {
    volume_type = "gp2"
    volume_size = 14
  }

  tags = {
    Name = "Ubuntu-Server-Instance"
  }

  connection {
    type     = "ssh"
    user     = "ubuntu"
    password = ""
    private_key = tls_private_key.private_key.private_key_openssh
    host        = self.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update && sudo apt upgrade -y",
      "sudo apt install -y python3 python3-pip ansible docker.io curl nano vim git && sudo apt autoremove --purge apache2 -y",
    ]
  }
  provisioner "local-exec" {
    command = "echo 'master ${self.public_ip}' >> ./files/hosts"
  }

  provisioner "local-exec" {
    command = "echo '[master]\n${self.public_ip}' > ./files/inventory.ini"
    }

  /*  
  provisioner "local-exec" {
    command = <<EOT
      ANSIBLE_CONFIG=${path.module}/ansible.cfg ansible-playbook -i ${path.module}/files/inventory.ini ${path.module}/playbook.yml
    EOT
  } */
}

output "instance_ip" {
  value = aws_instance.main_server.public_ip
}
