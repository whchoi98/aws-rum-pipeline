# terraform/modules/grafana/variables.tf

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 data lake bucket (read data + write Athena results)"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 data lake bucket"
  type        = string
}

variable "glue_database_name" {
  description = "Glue catalog database name (e.g. rum_pipeline_db)"
  type        = string
}

variable "tags" {
  description = "Additional resource tags"
  type        = map(string)
  default     = {}
}
