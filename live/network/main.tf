terraform {
  required_providers { aws = { source = "hashicorp/aws", version = "~> 5.60" } }
  backend "s3" {
    bucket         = "acme-lz-tfstate"
    key            = "network/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "lz-tf-locks"
    encrypt        = true
  }
}

variable "network_account_id" { type = string }
variable "organization_arn" { type = string }

provider "aws" {
  region = "us-east-1"
  assume_role { role_arn = "arn:aws:iam::${var.network_account_id}:role/OrganizationAccountAccessRole" }
}

module "egress_vpc" {
  source              = "../../modules/vpc"
  name                = "egress"
  cidr                = "10.0.0.0/16"
  segment             = "shared"
  flow_log_bucket_arn = "arn:aws:s3:::acme-org-flow-logs"
}

module "tgw" {
  source               = "../../modules/transit-gateway"
  organization_arn     = var.organization_arn
  egress_attachment_id = "tgw-attach-egress" # set after the egress VPC is attached
}

output "transit_gateway_id" { value = module.tgw.transit_gateway_id }
