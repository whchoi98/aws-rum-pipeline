# terraform/outputs.tf
output "api_endpoint" {
  description = "RUM API endpoint URL"
  value       = module.api_gateway.api_endpoint
}

output "s3_bucket_name" {
  description = "S3 data lake bucket name"
  value       = module.s3_data_lake.bucket_id
}

output "firehose_stream_name" {
  description = "Firehose delivery stream name"
  value       = module.firehose.delivery_stream_name
}

output "glue_database_name" {
  description = "Glue catalog database name"
  value       = module.glue_catalog.database_name
}

output "waf_acl_arn" {
  description = "WAF WebACL ARN"
  value       = module.security.waf_acl_arn
}

output "api_key_ssm_name" {
  description = "SSM parameter name for API keys"
  value       = module.security.api_key_ssm_name
}

output "grafana_workspace_endpoint" {
  description = "Amazon Managed Grafana workspace URL"
  value       = module.grafana.workspace_endpoint
}

output "grafana_workspace_id" {
  description = "Amazon Managed Grafana workspace ID"
  value       = module.grafana.workspace_id
}

output "athena_workgroup" {
  description = "Athena workgroup name for RUM queries"
  value       = module.grafana.athena_workgroup
}
