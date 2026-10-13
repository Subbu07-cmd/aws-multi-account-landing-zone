output "account_ids" { value = { for k, a in aws_organizations_account.acct : k => a.id } }
output "organization_arn" { value = aws_organizations_organization.this.arn }
