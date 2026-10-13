terraform {
  required_providers { aws = { source = "hashicorp/aws", version = "~> 5.60" } }
  backend "s3" {
    bucket         = "acme-lz-tfstate"
    key            = "workloads-nonprod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "lz-tf-locks"
    encrypt        = true
  }
}

variable "account_id" { type = string }
variable "transit_gateway_id" { type = string }

provider "aws" {
  region = "us-east-1"
  assume_role { role_arn = "arn:aws:iam::${var.account_id}:role/OrganizationAccountAccessRole" }
}

locals {
  environments = { dev = "10.20.0.0/16", staging = "10.30.0.0/16" }
}

module "vpc" {
  source              = "../../modules/vpc"
  for_each            = local.environments
  name                = each.key
  cidr                = each.value
  segment             = "nonprod"
  transit_gateway_id  = var.transit_gateway_id
  flow_log_bucket_arn = "arn:aws:s3:::acme-org-flow-logs"
  tags                = { Environment = each.key }
}

module "iam" {
  source = "../../modules/iam-baseline"
  deploy_roles = {
    "github-deploy-nonprod" = {
      repositories = ["Subbu07-cmd/enterprise-cicd-pipeline"]
      subject      = "ref:refs/heads/main"
      policy_arns  = ["arn:aws:iam::aws:policy/PowerUserAccess"]
    }
  }
}

module "security" {
  source          = "../../modules/security-baseline"
  region          = "us-east-1"
  log_bucket_name = "acme-org-audit-logs"
}
