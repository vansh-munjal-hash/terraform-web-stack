output "instance_id" {
  type        = string
  description = "ID of the EC2 instance"
  value       = component.web_server.instance_id
}

output "public_ip" {
  type        = string
  description = "Public IP address of the web server"
  value       = component.web_server.public_ip
}

output "public_dns" {
  type        = string
  description = "Public DNS name of the web server"
  value       = component.web_server.public_dns
}

output "web_url" {
  type        = string
  description = "URL to access the web application"
  value       = component.web_server.web_url
}

output "security_group_id" {
  type        = string
  description = "ID of the security group"
  value       = component.web_server.security_group_id
}
