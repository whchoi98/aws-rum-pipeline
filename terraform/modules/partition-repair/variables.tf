# terraform/modules/partition-repair/variables.tf

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "glue_database_name" {
  description = "Glue database name"
  type        = string
}

variable "glue_table_name" {
  description = "Glue table name to repair"
  type        = string
}

variable "athena_workgroup" {
  description = "Athena workgroup name"
  type        = string
}

variable "s3_bucket_arn" {
  description = "S3 data lake bucket ARN (for Athena query results)"
  type        = string
}

variable "lambda_source_dir" {
  description = "Path to the partition-repair Lambda source"
  type        = string
}

variable "schedule" {
  description = "EventBridge schedule expression"
  type        = string
  default     = "rate(15 minutes)"
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
