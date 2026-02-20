variable "aws_region" {
  type        = string
  description = "AWS region for deployment"
}

variable "environment" {
  type        = string
  description = "Environment name (dev/prod)"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
}

variable "role_arn" {
  type        = string
  description = "ARN of the AWS IAM role to assume via OIDC"
}

variable "identity_token" {
  type        = string
  description = "OIDC identity token for AWS authentication"
  ephemeral   = true
}

variable "project_name" {
  type        = string
  description = "Project name for resource naming"
  default     = "web-app"
}

variable "eip_allocation_id" {
  type        = string
  description = "Elastic IP allocation ID to import"
  default     = ""
}
