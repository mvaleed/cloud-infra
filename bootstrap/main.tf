# =============================================================================
# Bootstrap Configuration — Terraform State & GitHub Actions OIDC
# =============================================================================
#
# PURPOSE:
#   One-time setup to create the foundational resources that Terraform itself
#   needs to operate. This solves the chicken-and-egg problem: 
#
# WHAT THIS CREATES:
#   1. S3 bucket for Terraform remote state (versioned, encrypted, private)
#   2. GitHub OIDC identity provider (tells AWS to trust GitHub tokens)
#   3. IAM role for GitHub Actions to assume (with OIDC trust policy)
#
# HOW TO RUN (once, from your laptop):
#   cd bootstrap/
#   terraform init
#   terraform plan
#   terraform apply
# =============================================================================

terraform {
  required_version = ">= 1.14.6"

  # Local backend — this bootstrap has no remote state (it IS the remote state setup)
  # After first run, you can optionally migrate this to the S3 bucket it creates
  backend "local" {
    path = "terraform.tfstate"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Project   = "bootstrap"
      Repo      = "mvaleed/cloud-infra"
    }
  }
}
