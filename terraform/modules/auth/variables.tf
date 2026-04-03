# terraform/modules/auth/variables.tf

variable "project_name" {
  description = "프로젝트 이름"
  type        = string
}

variable "cloudfront_domain" {
  description = "CloudFront 도메인 (콜백 URL 생성용)"
  type        = string
}

variable "sso_metadata_url" {
  description = "SSO SAML 메타데이터 URL (IAM Identity Center)"
  type        = string
  default     = ""
}

variable "sso_provider_name" {
  description = "SSO Identity Provider 이름"
  type        = string
  default     = "AWSSSOProvider"
}

variable "lambda_source_dir" {
  description = "Lambda@Edge 소스 디렉터리"
  type        = string
}

variable "cognito_domain_prefix" {
  description = "Cognito Hosted UI 도메인 접두사"
  type        = string
  default     = ""
}

variable "tags" {
  description = "리소스 태그"
  type        = map(string)
  default     = {}
}
