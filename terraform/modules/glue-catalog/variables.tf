variable "project_name" {
  description = "Project name for database naming"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 data lake bucket name for table locations"
  type        = string
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
