data "aws_caller_identity" "current" {}

locals {
  mgmt       = var.is_management_account ? 1 : 0
  account_id = data.aws_caller_identity.current.account_id
}

# Customer-managed key for the trail, its CloudWatch log group and its SNS topic.
resource "aws_kms_key" "audit" {
  count                   = local.mgmt
  description             = "Organization audit trail"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "CloudTrailEncrypt"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = ["kms:GenerateDataKey*", "kms:DescribeKey", "kms:Decrypt"]
        Resource  = "*"
      },
      {
        Sid       = "CloudWatchLogsEncrypt"
        Effect    = "Allow"
        Principal = { Service = "logs.${var.region}.amazonaws.com" }
        Action    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource  = "*"
      },
    ]
  })
}

# Stream the trail into CloudWatch Logs for metric filters and alarms (CKV2_AWS_10)
resource "aws_cloudwatch_log_group" "trail" {
  count             = local.mgmt
  name              = "/aws/cloudtrail/org-trail"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.audit[0].arn
}

resource "aws_iam_role" "trail_to_cwl" {
  count = local.mgmt
  name  = "cloudtrail-to-cloudwatch"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "cloudtrail.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "trail_to_cwl" {
  count = local.mgmt
  name  = "write-trail-logs"
  role  = aws_iam_role.trail_to_cwl[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.trail[0].arn}:*"
    }]
  })
}

# Notify on every log file delivery (CKV_AWS_252)
resource "aws_sns_topic" "trail" {
  count             = local.mgmt
  name              = "org-trail-delivery"
  kms_master_key_id = aws_kms_key.audit[0].id
}

resource "aws_sns_topic_policy" "trail" {
  count = local.mgmt
  arn   = aws_sns_topic.trail[0].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "CloudTrailPublish"
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.trail[0].arn
    }]
  })
}

resource "aws_cloudtrail" "org" {
  count                         = local.mgmt
  name                          = "org-trail"
  s3_bucket_name                = var.log_bucket_name
  is_organization_trail         = true
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  kms_key_id                    = coalesce(var.kms_key_arn, aws_kms_key.audit[0].arn)
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.trail[0].arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.trail_to_cwl[0].arn
  sns_topic_name                = aws_sns_topic.trail[0].name

  depends_on = [aws_iam_role_policy.trail_to_cwl, aws_sns_topic_policy.trail]
}

resource "aws_iam_role" "config" {
  name = "aws-config-recorder"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "config.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_config_configuration_recorder" "this" {
  name     = "default"
  role_arn = aws_iam_role.config.arn
  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "this" {
  name           = "default"
  s3_bucket_name = var.log_bucket_name
  depends_on     = [aws_config_configuration_recorder.this]
}

resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.this]
}

locals {
  managed_rules = {
    "encrypted-volumes"                = "ENCRYPTED_VOLUMES"
    "s3-bucket-public-read-prohibited" = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
    "root-account-mfa-enabled"         = "ROOT_ACCOUNT_MFA_ENABLED"
    "restricted-ssh"                   = "INCOMING_SSH_DISABLED"
    "rds-storage-encrypted"            = "RDS_STORAGE_ENCRYPTED"
    "iam-user-no-policies-check"       = "IAM_USER_NO_POLICIES_CHECK"
    "cloudtrail-enabled"               = "CLOUD_TRAIL_ENABLED"
  }
}

resource "aws_config_config_rule" "managed" {
  for_each = local.managed_rules
  name     = each.key
  source {
    owner             = "AWS"
    source_identifier = each.value
  }
  depends_on = [aws_config_configuration_recorder.this]
}

resource "aws_guardduty_detector" "this" {
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
}

# Org-wide GuardDuty (CKV2_AWS_3): new member accounts are enrolled automatically.
resource "aws_guardduty_organization_configuration" "this" {
  count                            = local.mgmt
  detector_id                      = aws_guardduty_detector.this.id
  auto_enable_organization_members = "ALL"
}

resource "aws_securityhub_account" "this" {}

resource "aws_securityhub_standards_subscription" "fsbp" {
  standards_arn = "arn:aws:securityhub:${var.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.this]
}

resource "aws_ebs_encryption_by_default" "this" { enabled = true }

resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
