# Multi-Account AWS Cloud Infrastructure Platform

> **About this repo:** my production work lives in private enterprise repositories, so this is a public reference build of the same patterns, written from scratch with sample data and placeholder account IDs.

A secure, **multi-account AWS landing zone** built with Terraform. It covers an AWS Organizations layout with guardrail SCPs, hub-and-spoke **Transit Gateway** networking, standard **VPCs**, **IAM boundary design**, a **security baseline** (CloudTrail, Config, GuardDuty, Security Hub), **cross-account CI/CD** with GitHub OIDC, and **Ansible** for OS-level hardening of EC2 hosts.

```
                       ┌─────────────────────────── AWS Organization ───────────────────────────┐
                       │  SCPs: deny root, deny region drift, protect CloudTrail/Config/GuardDuty │
                       └────────────────────────────────────────────────────────────────────────┘
   management            network (hub)                  workloads-nonprod          workloads-prod
 ┌──────────────┐     ┌─────────────────────┐        ┌───────────────────┐      ┌───────────────────┐
 │ Organizations│     │  Transit Gateway    │◀──────▶│ VPC dev 10.20/16  │      │ VPC prod 10.40/16 │
 │ CloudTrail   │     │  egress VPC + NAT   │◀──────▶│ VPC stg 10.30/16  │◀────▶│ EKS / RDS / EC2   │
 │ SSO / IAM IC │     │  RAM share          │        └───────────────────┘      └───────────────────┘
 └──────────────┘     └─────────────────────┘          prod and nonprod route tables are isolated
```

## Layout

| Path | Purpose |
|------|---------|
| `modules/organization` | OUs, member accounts and service control policies |
| `modules/vpc` | Standard 3-AZ VPC with private, public and TGW subnets and flow logs |
| `modules/transit-gateway` | TGW, RAM share, and isolated prod and nonprod route tables |
| `modules/iam-baseline` | Permission boundary, GitHub OIDC provider and cross-account deploy roles |
| `modules/security-baseline` | CloudTrail, AWS Config with conformance rules, GuardDuty and Security Hub |
| `live/*` | One Terraform root per account, each with its own state |
| `ansible/` | RHEL/Amazon Linux baseline: SSH hardening, auditd, chrony and the CloudWatch agent |
| `.github/workflows/` | Plan on PR and apply on merge, assuming a per-account role through OIDC |

## Guardrails

- **SCPs** deny root user actions, disallowed regions, leaving the organization and disabling CloudTrail, Config or GuardDuty
- **Permission boundary** on every role that CI creates, so CI can't escalate privileges
- **Least-privilege deploy roles** that GitHub OIDC can only assume from `main` of an allowed repository
- **Continuous compliance**: AWS Config managed rules (encrypted volumes, S3 public access, root MFA, restricted SSH)

## Checkov findings and how they were resolved

The first scan reported 14 failed checks. Each one was either fixed or accepted on purpose with a written reason:

| Check | Finding | Resolution |
|------|---------|-----------|
| CKV_AWS_394 | AZ data source can silently gain zones | VPC module takes a pinned, validated `azs` list |
| CKV_AWS_331 | Transit Gateway auto-accepts attachments | Auto-accept disabled; reviewed spokes accepted explicitly through `accepted_attachments` |
| CKV_AWS_252 | CloudTrail has no SNS topic | KMS-encrypted SNS topic notified on each log delivery |
| CKV2_AWS_10 | CloudTrail not sent to CloudWatch Logs | Trail streams to a KMS-encrypted log group (365-day retention) for metric filters and alarms |
| CKV2_AWS_3 | GuardDuty not org-wide | `aws_guardduty_organization_configuration` auto-enrolls every member account |
| CKV_AWS_107/108/109/111/356 | Broad actions in the IAM policy | **Accepted**: it's a permissions *boundary*, a ceiling and not a grant. Secrets, SSM and KMS access were still narrowed to account-scoped ARNs. |

## Usage

```bash
cd live/network
terraform init
terraform plan
terraform apply
```

New environment = new `live/<account>` folder plus a `vpc` module call with a free CIDR.

## Tech

AWS (VPC, IAM, Transit Gateway, EC2, EKS, S3, RDS) · Terraform · Ansible · GitHub Actions · CloudWatch
