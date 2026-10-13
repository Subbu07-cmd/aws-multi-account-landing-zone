data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# Every role created by automation must carry this boundary, which blocks privilege escalation.
data "aws_iam_policy_document" "boundary" {
  statement {
    sid       = "AllowWorkloadServices"
    actions   = ["ec2:*", "eks:*", "ecr:*", "rds:*", "s3:*", "logs:*", "cloudwatch:*", "elasticloadbalancing:*", "autoscaling:*", "kms:Decrypt", "kms:GenerateDataKey*", "secretsmanager:GetSecretValue", "ssm:Get*"]
    resources = ["*"]
  }
  statement {
    sid       = "AllowRoleManagementOnlyWithBoundary"
    actions   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary", "iam:AttachRolePolicy", "iam:PutRolePolicy"]
    resources = ["arn:aws:iam::${local.account_id}:role/app/*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = ["arn:aws:iam::${local.account_id}:policy/workload-boundary"]
    }
  }
  statement {
    sid       = "DenyBoundaryTampering"
    effect    = "Deny"
    actions   = ["iam:DeletePolicy", "iam:CreatePolicyVersion", "iam:DeleteRolePermissionsBoundary"]
    resources = ["arn:aws:iam::${local.account_id}:policy/workload-boundary", "arn:aws:iam::${local.account_id}:role/*"]
  }
}

resource "aws_iam_policy" "boundary" {
  name   = "workload-boundary"
  policy = data.aws_iam_policy_document.boundary.json
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "github_trust" {
  for_each = var.deploy_roles
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for r in each.value.repositories : "repo:${r}:${each.value.subject}"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  for_each             = var.deploy_roles
  name                 = each.key
  assume_role_policy   = data.aws_iam_policy_document.github_trust[each.key].json
  permissions_boundary = aws_iam_policy.boundary.arn
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "deploy" {
  for_each   = { for pair in flatten([for role, cfg in var.deploy_roles : [for p in cfg.policy_arns : { role = role, arn = p }]]) : "${pair.role}|${pair.arn}" => pair }
  role       = aws_iam_role.deploy[each.value.role].name
  policy_arn = each.value.arn
}

resource "aws_iam_account_password_policy" "strict" {
  minimum_password_length        = 16
  require_symbols                = true
  require_numbers                = true
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  max_password_age               = 90
  password_reuse_prevention      = 24
  allow_users_to_change_password = true
}
