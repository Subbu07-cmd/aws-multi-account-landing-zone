variable "region" { type = string }
variable "log_bucket_name" { type = string }
variable "kms_key_arn" {
  type    = string
  default = null
}
variable "is_management_account" {
  type    = bool
  default = false
}
