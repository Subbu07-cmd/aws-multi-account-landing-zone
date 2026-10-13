data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# Every role created by automation must carry this boundary, which blocks privilege escalation.
# A permissions boundary is a ceiling, not a grant: a role's effective permissions are the
# intersection of the boundary and its attached policies. Service-level wildcards are therefore
# intentional here; least privilege is enforced by each role's own policy.
data "aws_iam_policy_document" "boundary" {
  # checkov:skip=CKV_AWS_107:Permissions boundary (ceiling); credential access is limited by attached policies
  # checkov:skip=CKV_AWS_108:Permissions boundary (ceiling); data access is limited by attached policies
  # checkov:skip=CKV_AWS_109:Permissions boundary (ceiling); IAM changes are constrained by the boundary condition below
  # checkov:skip=CKV_AWS_111:Permissions boundary (ceiling); write access is granted only by attached policies
  # checkov:skip=CKV_AWS_356:Permissions boundary (ceiling); resource scoping lives in attached policies
  statement {
    sid       = "AllowWorkloadServices"
    actions   = ["ec2:*", "eks:*", "ecr:*", "rds:*", "s3:*", "logs:*", "cloudwatch:*", "elasticloadbalancing:*", "autoscaling:*"]
    resources = ["*"]
  }
  statement {
    sid     = "AllowAccountScopedSecretsAndKeys"
    actions = ["kms:Decrypt", "kms:GenerateDataKey*", "secretsmanager:GetSecretValue", "ssm:GetParameter*"]
    resources = [
      "arn:aws:kms:*:${local.account_id}:key/*",
      "arn:aws:secretsmanager:*:${local.account_id}:secret:*",
      "arn:aws:ssm:*:${local.account_id}:parameter/*",
    ]
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
