resource "aws_organizations_organization" "this" {
  feature_set          = "ALL"
  enabled_policy_types = ["SERVICE_CONTROL_POLICY"]
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com", "config.amazonaws.com", "guardduty.amazonaws.com",
    "securityhub.amazonaws.com", "sso.amazonaws.com", "ram.amazonaws.com",
  ]
}

resource "aws_organizations_organizational_unit" "ou" {
  for_each  = toset(["Security", "Infrastructure", "Workloads-NonProd", "Workloads-Prod"])
  name      = each.key
  parent_id = aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_account" "acct" {
  for_each  = var.accounts
  name      = each.key
  email     = each.value.email
  parent_id = aws_organizations_organizational_unit.ou[each.value.ou].id
  role_name = "OrganizationAccountAccessRole"

  lifecycle { ignore_changes = [role_name] }
}

data "aws_iam_policy_document" "guardrails" {
  statement {
    sid       = "DenyRootUser"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:root"]
    }
  }
  statement {
    sid    = "DenyUnapprovedRegions"
    effect = "Deny"
    not_actions = [
      "iam:*", "organizations:*", "sts:*", "support:*", "cloudfront:*",
      "route53:*", "budgets:*", "health:*", "sso:*",
    ]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = var.allowed_regions
    }
  }
  statement {
    sid    = "ProtectSecurityServices"
    effect = "Deny"
    actions = [
      "cloudtrail:StopLogging", "cloudtrail:DeleteTrail",
      "config:StopConfigurationRecorder", "config:DeleteConfigurationRecorder",
      "guardduty:DeleteDetector", "guardduty:DisassociateFromMasterAccount",
      "securityhub:DisableSecurityHub", "organizations:LeaveOrganization",
    ]
    resources = ["*"]
  }
}

resource "aws_organizations_policy" "guardrails" {
  name    = "baseline-guardrails"
  type    = "SERVICE_CONTROL_POLICY"
  content = data.aws_iam_policy_document.guardrails.json
}

resource "aws_organizations_policy_attachment" "guardrails" {
  for_each  = aws_organizations_organizational_unit.ou
  policy_id = aws_organizations_policy.guardrails.id
  target_id = each.value.id
}
