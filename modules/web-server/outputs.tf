output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.web_server.id
}

output "public_ip" {
  description = "Public IP address of the web server"
  value       = aws_instance.web_server.public_ip
}

output "public_dns" {
  description = "Public DNS name of the web server"
  value       = aws_instance.web_server.public_dns
}

output "web_url" {
  description = "URL to access the web application"
  value       = "http://${aws_instance.web_server.public_ip}"
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.web_server.id
}

# EIP outputs removed - EIPs are no longer managed by Terraform
# output "elastic_ip" {
#   description = "Elastic IP address (if imported)"
#   value       = length(aws_eip.web) > 0 ? aws_eip.web[0].public_ip : null
# }
#
# output "elastic_ip_allocation_id" {
#   description = "Elastic IP allocation ID (if imported)"
#   value       = length(aws_eip.web) > 0 ? aws_eip.web[0].allocation_id : null
# }
