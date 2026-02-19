required_providers {
  aws = {
    source  = "hashicorp/aws"
    version = "~> 5.7.0"
  }
}

provider "aws" "this" {
  config {
    region = var.aws_region

    assume_role_with_web_identity {
      role_arn           = var.role_arn
      web_identity_token = var.identity_token
    }

    default_tags {
      tags = {
        Project     = var.project_name
        Environment = var.environment
        ManagedBy   = "Terraform Stacks"
      }
    }
  }
}
