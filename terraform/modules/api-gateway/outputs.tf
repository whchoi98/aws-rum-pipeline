# terraform/modules/api-gateway/outputs.tf
output "api_endpoint" {
  description = "HTTP API invoke URL"
  value       = aws_apigatewayv2_api.rum.api_endpoint
}

output "api_id" {
  description = "HTTP API ID"
  value       = aws_apigatewayv2_api.rum.id
}

output "ingest_lambda_arn" {
  description = "Ingest Lambda function ARN"
  value       = aws_lambda_function.ingest.arn
}
