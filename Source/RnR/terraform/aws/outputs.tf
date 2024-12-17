output "instance_private_ip" {
  description = "The private IP address of the replace_n_route instance"
  value       = aws_instance.replace_n_route.private_ip
}
