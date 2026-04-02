# terraform/modules/security/outputs.tf
output "authorizer_invoke_arn" {
  description = "Authorizer Lambda invoke ARN"
  value       = aws_lambda_function.authorizer.invoke_arn
}

output "authorizer_function_name" {
  description = "Authorizer Lambda function name"
  value       = aws_lambda_function.authorizer.function_name
}

output "waf_acl_arn" {
  description = "WAF WebACL ARN"
  value       = aws_wafv2_web_acl.rum.arn
}

output "api_key_ssm_name" {
  description = "SSM parameter name containing API keys"
  value       = aws_ssm_parameter.api_keys.name
}

output "initial_api_key" {
  description = "Initial generated API key (retrieve from SSM after deploy)"
  value       = random_password.api_key.result
  sensitive   = true
}
