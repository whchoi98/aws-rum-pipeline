# terraform/variables.tf
variable "aws_region" {
  description = "AWS region for RUM pipeline"
  type        = string
  default     = "ap-northeast-2"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "rum-pipeline"
}

variable "vpc_id" {
  description = "VPC ID for Agent UI deployment"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for Agent UI ALB"
  type        = list(string)
}

variable "agentcore_endpoint_arn" {
  description = "Bedrock AgentCore runtime endpoint ARN"
  type        = string
}

variable "sso_metadata_url" {
  description = "SSO SAML metadata URL (IAM Identity Center). 빈 문자열이면 SSO 비활성화."
  type        = string
  default     = ""
}

variable "allowed_origins" {
  description = "CORS allowed origins for the API"
  type        = list(string)
  default     = ["*"]
}
