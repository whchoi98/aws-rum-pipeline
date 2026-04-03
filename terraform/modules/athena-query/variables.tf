variable "project_name" {
  type = string
}
variable "glue_database_name" {
  type = string
}
variable "athena_workgroup" {
  type = string
}
variable "s3_bucket_arn" {
  type = string
}
variable "lambda_source_dir" {
  type = string
}
variable "tags" {
  type    = map(string)
  default = {}
}
