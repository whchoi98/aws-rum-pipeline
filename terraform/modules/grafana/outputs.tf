# terraform/modules/grafana/outputs.tf

output "workspace_endpoint" {
  description = "Amazon Managed Grafana workspace endpoint URL"
  value       = "https://${aws_grafana_workspace.rum.endpoint}"
}

output "workspace_id" {
  description = "Amazon Managed Grafana workspace ID"
  value       = aws_grafana_workspace.rum.id
}

output "athena_workgroup" {
  description = "Athena workgroup name for RUM dashboard queries"
  value       = aws_athena_workgroup.rum.name
}

output "grafana_role_arn" {
  description = "IAM role ARN used by the Grafana workspace"
  value       = aws_iam_role.grafana.arn
}
