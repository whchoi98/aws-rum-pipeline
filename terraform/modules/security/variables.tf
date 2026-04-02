# terraform/modules/security/variables.tf
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "rate_limit" {
  description = "WAF rate limit: max requests per 5-minute window per IP"
  type        = number
  default     = 2000
}

variable "lambda_source_dir" {
  description = "Path to the authorizer Lambda source directory"
  type        = string
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
