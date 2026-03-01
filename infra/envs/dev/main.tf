terraform {
  required_version = ">= 1.14.6"

  backend "s3" {
    bucket       = "mvaleed-terraform-state-129580962636"
    key          = "cloud-infra/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "terraform"
      Repo        = "mvaleed/cloud-infra"
    }
  }
}


variable "region" {
  description = "AWS region"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

# -----------------------------------------------------------------------------
# Example: uncomment and add modules as you build out infra
# -----------------------------------------------------------------------------
#
# module "vpc" {
#   source      = "../../modules/vpc"
#   environment = var.environment
#   cidr_block  = "10.0.0.0/16"
# }
