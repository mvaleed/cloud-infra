variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "project_name" {
  type    = string
  default = "mvaleed-platform" # Your project codename
}

# VPC
variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
}

# EKS
variable "cluster_version" {
  type    = string
  default = "1.34"
}

# RDS
variable "db_master_username" {
  type    = string
  default = "app_admin"
}

variable "db_master_password" {
  type      = string
  sensitive = true
  # We'll pass this via tfvars or env var TF_VAR_db_master_password
  # PROD: Use AWS Secrets Manager with random password generation
  # instead. The RDS module supports `manage_master_user_password = true`
  # which lets AWS handle rotation automatically.
}
