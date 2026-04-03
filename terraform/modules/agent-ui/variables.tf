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
variable "tags" {
  type    = map(string)
  default = {}
}
