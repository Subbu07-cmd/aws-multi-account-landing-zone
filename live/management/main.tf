terraform {
  required_providers { aws = { source = "hashicorp/aws", version = "~> 5.60" } }
  backend "s3" {
    bucket         = "acme-lz-tfstate"
    key            = "management/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "lz-tf-locks"
    encrypt        = true
  }
}

provider "aws" { region = "us-east-1" }

module "organization" {
  source = "../../modules/organization"
  accounts = {
    "network"           = { email = "aws+network@example.com", ou = "Infrastructure" }
    "security-audit"    = { email = "aws+audit@example.com", ou = "Security" }
    "workloads-nonprod" = { email = "aws+nonprod@example.com", ou = "Workloads-NonProd" }
    "workloads-prod"    = { email = "aws+prod@example.com", ou = "Workloads-Prod" }
  }
}

module "security" {
  source                = "../../modules/security-baseline"
  region                = "us-east-1"
  log_bucket_name       = "acme-org-audit-logs"
  is_management_account = true
}

output "account_ids" { value = module.organization.account_ids }
