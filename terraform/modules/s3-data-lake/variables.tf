variable "project_name" {
  description = "Project name for bucket naming"
  type        = string
}

variable "account_id" {
  description = "AWS account ID for globally unique bucket name"
  type        = string
}

variable "raw_expiration_days" {
  description = "Days before raw data expires"
  type        = number
  default     = 90
}

variable "error_expiration_days" {
  description = "Days before error records expire"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
