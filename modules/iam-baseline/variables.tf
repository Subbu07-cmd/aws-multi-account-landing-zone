variable "deploy_roles" {
  description = "GitHub OIDC deploy roles: name => { repositories, subject, policy_arns }"
  type = map(object({
    repositories = list(string)
    subject      = string # e.g. "ref:refs/heads/main" or "environment:prod"
    policy_arns  = list(string)
  }))
  default = {}
}
