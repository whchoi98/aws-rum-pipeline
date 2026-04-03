variable "project_name" {
  type = string
}
variable "vpc_id" {
  type = string
}
variable "public_subnet_ids" {
  type = list(string)
}
variable "instance_type" {
  type    = string
  default = "t4g.large"
}
variable "agentcore_endpoint_arn" {
  type = string
}
variable "edge_auth_qualified_arn" {
  description = "Lambda@Edge viewer-request 버전 ARN (인증)"
  type        = string
  default     = ""
}
variable "tags" {
  type    = map(string)
  default = {}
}
