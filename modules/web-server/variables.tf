variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "web-app"
}
