output "boundary_arn" { value = aws_iam_policy.boundary.arn }
output "deploy_role_arns" { value = { for k, r in aws_iam_role.deploy : k => r.arn } }
