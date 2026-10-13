variable "name" { type = string }
variable "cidr" { type = string }
variable "azs" {
  description = "Exactly three Availability Zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
  validation {
    condition     = length(var.azs) == 3
    error_message = "Provide exactly three Availability Zones."
  }
}
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
