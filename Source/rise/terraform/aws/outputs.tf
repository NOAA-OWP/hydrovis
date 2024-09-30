output "instance_private_ip" {
  description = "The private IP address of the rise instance"
  value       = aws_instance.rise.private_ip
}
