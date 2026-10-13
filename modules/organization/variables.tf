variable "accounts" {
  description = "Member accounts: name => { email, ou }"
  type        = map(object({ email = string, ou = string }))
}
variable "allowed_regions" {
  type    = list(string)
  default = ["us-east-1", "us-west-2"]
}
