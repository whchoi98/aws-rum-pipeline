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

variable "allowed_origins" {
  description = "CORS allowed origins for the API"
  type        = list(string)
  default     = ["*"]
}
