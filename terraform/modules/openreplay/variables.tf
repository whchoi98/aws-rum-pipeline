# terraform/modules/openreplay/variables.tf
# OpenReplay 모듈 입력 변수

variable "project_name" {
  type = string
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "instance_type" {
  type    = string
  default = "m7g.xlarge"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.medium"
}

variable "edge_auth_qualified_arn" {
  description = "Lambda@Edge SSO ARN (빈 문자열이면 비활성)"
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
