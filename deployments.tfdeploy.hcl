# OIDC identity token for AWS authentication
identity_token "aws" {
  audience = ["aws.workload.identity"]
}

# Local values for reusable configuration
locals {
  # IMPORTANT: Replace this with your actual AWS IAM role ARN
  # This role must be configured to trust HCP Terraform's OIDC provider
  role_arn = "arn:aws:iam::062852074709:role/vansh-stack-role"

  project_name = "web-app"
}

# Development environment deployment
deployment "dev" {
  inputs = {
    aws_region        = "us-east-1"
    environment       = "dev"
    instance_type     = "t3.nano"  # ~$3.80/month (730 hours)
    role_arn          = local.role_arn
    identity_token    = identity_token.aws.jwt
    project_name      = local.project_name
    eip_allocation_id = "eipalloc-0860eb1e7695c117f"  # Dev EIP
  }

  destroy = true
}

# Production environment deployment
deployment "prod" {
  inputs = {
    aws_region        = "us-west-2"
    environment       = "prod"
    instance_type     = "t3.small"  # ~$15/month for better performance
    role_arn          = local.role_arn
    identity_token    = identity_token.aws.jwt
    project_name      = local.project_name
    eip_allocation_id = "eipalloc-0573d89410f3ab8bf"  # Prod EIP
  }

  destroy = true
}
