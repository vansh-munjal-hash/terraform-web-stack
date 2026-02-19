output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.web.id
}

output "public_ip" {
  description = "Public IP address of the web server"
  value       = aws_instance.web.public_ip
}

output "public_dns" {
  description = "Public DNS name of the web server"
  value       = aws_instance.web.public_dns
}

output "web_url" {
  description = "URL to access the web application"
  value       = "http://${aws_instance.web.public_ip}"
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.web.id
}
