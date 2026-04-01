# terraform/modules/firehose/variables.tf
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 data lake bucket"
  type        = string
}

variable "glue_database_name" {
  description = "Glue catalog database name"
  type        = string
}

variable "glue_table_name" {
  description = "Glue catalog table name for Parquet schema"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "lambda_source_dir" {
  description = "Path to the transform Lambda source directory"
  type        = string
}

variable "buffering_size_mb" {
  description = "Firehose buffer size in MB (min 64 with dynamic partitioning)"
  type        = number
  default     = 64
}

variable "buffering_interval_sec" {
  description = "Firehose buffer interval in seconds"
  type        = number
  default     = 60
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
