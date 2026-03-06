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
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.37"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
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

# -------------------------------------------------------------------
# Kubernetes & Helm Providers
# -------------------------------------------------------------------
# Auth uses the AWS CLI exec plugin -- same mechanism as
# `aws eks update-kubeconfig`. Whoever runs terraform (laptop or CI)
# needs the aws CLI and permissions for eks:DescribeCluster.
#
# We use exec (not the data source token method) because the token
# is short-lived (15 min) and can expire during long applies.
# The exec plugin refreshes it automatically.

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}
