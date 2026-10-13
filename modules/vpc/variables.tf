variable "name" { type = string }
variable "cidr" { type = string }
variable "segment" {
  description = "prod | nonprod | shared — selects the TGW route table"
  type        = string
}
variable "transit_gateway_id" {
  type    = string
  default = null
}
variable "flow_log_bucket_arn" { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}
