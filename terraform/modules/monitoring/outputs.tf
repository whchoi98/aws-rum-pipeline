# terraform/modules/monitoring/outputs.tf

output "dashboard_name" {
  description = "CloudWatch dashboard name"
  value       = aws_cloudwatch_dashboard.rum.dashboard_name
}
