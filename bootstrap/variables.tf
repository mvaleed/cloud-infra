variable "aws_region" {
  description = "AWS region for the state bucket and provider config"
  type        = string
  default     = "us-east-1"
}

variable "github_repo" {
  description = "GitHub repository in `owner/repo` format. This is used in the IAM trust policy to control which repo can assume"
  type        = string
  default     = "mvaleed/cloud-infra"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$", var.github_repo))
    error_message = "github_repo must be in 'owner/repo' format (e.g., 'mvaleed/cloud-infra')."
  }
}

variable "state_bucket_prefix" {
  description = "Prefix for the S3 state bucket name. Account ID is appended automatically."
  type        = string
  default     = "mvaleed-terraform-state"
}
