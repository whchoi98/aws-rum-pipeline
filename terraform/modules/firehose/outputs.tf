# terraform/modules/firehose/outputs.tf
output "delivery_stream_name" {
  description = "Firehose delivery stream name"
  value       = aws_kinesis_firehose_delivery_stream.rum_events.name
}

output "delivery_stream_arn" {
  description = "Firehose delivery stream ARN"
  value       = aws_kinesis_firehose_delivery_stream.rum_events.arn
}

output "transform_lambda_arn" {
  description = "Transform Lambda function ARN"
  value       = aws_lambda_function.transform.arn
}
