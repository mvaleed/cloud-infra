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
      version = "6.35.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "terraform"
      Repo        = "mvaleed/cloud-infra"
    }
  }
}
