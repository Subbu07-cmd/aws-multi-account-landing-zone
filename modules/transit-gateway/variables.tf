variable "asn" {
  type    = number
  default = 64512
}
variable "organization_arn" { type = string }
variable "egress_attachment_id" {
  description = "Attachment ID of the shared egress VPC"
  type        = string
}
variable "tags" {
  type    = map(string)
  default = {}
}
