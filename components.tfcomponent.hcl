component "web_server" {
  source = "./modules/web-server"

  inputs = {
    instance_type = var.instance_type
    environment   = var.environment
    aws_region    = var.aws_region
    project_name  = var.project_name
  }

  providers = {
    aws = provider.aws.this
  }
}
