terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      configuration_aliases = [aws]
    }
  }
}

# Get the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get default VPC (to minimize costs by not creating new VPC)
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security group for web server
resource "aws_security_group" "web" {
  name_prefix = "${var.project_name}-${var.environment}-"
  description = "Security group for ${var.environment} web server"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-sg"
    Environment = var.environment
    ManagedBy   = "Terraform Stacks"
  }
}

# User data script to install and configure nginx
locals {
  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y nginx

    cat > /usr/share/nginx/html/index.html <<'HTML'
    <!DOCTYPE html>
    <html>
    <head>
        <title>Welcome to ${var.environment}</title>
        <style>
            body {
                font-family: Arial, sans-serif;
                margin: 50px;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
            }
            .container {
                background: rgba(255,255,255,0.1);
                padding: 40px;
                border-radius: 10px;
                backdrop-filter: blur(10px);
            }
            h1 { font-size: 3em; margin: 0; }
            .env {
                background: rgba(255,255,255,0.2);
                padding: 10px 20px;
                border-radius: 5px;
                display: inline-block;
                margin-top: 20px;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🚀 Web App Deployed!</h1>
            <div class="env">Environment: <strong>${upper(var.environment)}</strong></div>
            <p>Region: ${var.aws_region}</p>
            <p>Instance Type: ${var.instance_type}</p>
            <p>Deployed with Terraform Stacks using OIDC authentication</p>
        </div>
    </body>
    </html>
    HTML

    systemctl start nginx
    systemctl enable nginx
  EOF
}

# EC2 instance for web server
resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.web.id]
  subnet_id              = data.aws_subnets.default.ids[0]

  user_data                   = local.user_data
  user_data_replace_on_change = true

  tags = {
    Name        = "${var.project_name}-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform Stacks"
  }
}
