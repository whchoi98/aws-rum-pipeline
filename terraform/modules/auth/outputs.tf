# terraform/modules/auth/outputs.tf

output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.agent_users.id
}

output "user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.agent_users.arn
}

output "client_id" {
  description = "Cognito App Client ID"
  value       = aws_cognito_user_pool_client.agent_app.id
}

output "cognito_domain" {
  description = "Cognito Hosted UI 도메인"
  value       = "${local.cognito_domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
}

output "edge_auth_qualified_arn" {
  description = "Lambda@Edge 버전 ARN (CloudFront 연결용)"
  value       = aws_lambda_function.edge_auth.qualified_arn
}

output "login_url" {
  description = "Cognito 로그인 URL"
  value       = "https://${local.cognito_domain}.auth.${data.aws_region.current.name}.amazoncognito.com/oauth2/authorize?client_id=${aws_cognito_user_pool_client.agent_app.id}&response_type=code&scope=openid+email+profile&redirect_uri=${local.callback_url}"
}
