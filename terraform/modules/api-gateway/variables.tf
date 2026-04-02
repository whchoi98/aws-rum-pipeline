# terraform/modules/api-gateway/variables.tf
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "firehose_stream_name" {
  description = "Firehose delivery stream name (passed to ingest Lambda env var)"
  type        = string
}

variable "firehose_stream_arn" {
  description = "Firehose delivery stream ARN (for Lambda IAM policy)"
  type        = string
}

variable "lambda_source_dir" {
  description = "Path to the ingest Lambda source directory"
  type        = string
}

variable "allowed_origins" {
  description = "CORS allowed origins"
  type        = list(string)
  default     = ["*"]
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}

variable "authorizer_invoke_arn" {
  description = "Lambda Authorizer invoke ARN"
  type        = string
  default     = null
}

variable "waf_acl_arn" {
  description = "WAF WebACL ARN to associate with API stage"
  type        = string
  default     = null
}

variable "authorizer_function_name" {
  description = "Lambda Authorizer function name (for invoke permission)"
  type        = string
  default     = null
}
