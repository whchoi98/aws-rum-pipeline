output "cloudfront_url" {
  description = "CloudFront distribution URL (HTTPS)"
  value       = "https://${aws_cloudfront_distribution.agent.domain_name}"
}

output "cloudfront_domain" {
  description = "CloudFront domain name"
  value       = aws_cloudfront_distribution.agent.domain_name
}

output "alb_dns" {
  description = "ALB DNS name"
  value       = aws_lb.agent.dns_name
}

output "ec2_instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.agent_ui.id
}

output "ec2_private_ip" {
  description = "EC2 private IP"
  value       = aws_instance.agent_ui.private_ip
}
