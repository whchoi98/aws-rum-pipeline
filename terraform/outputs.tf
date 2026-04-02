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
