output "state_bucket_name" {
  description = "S3 bucket name for Terraform state. Use in backend.tf 'bucket' field."
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.terraform_state.arn
}

output "plan_role_arn" {
  description = "IAM role ARN for terraform plan (read-only, used on PR branches)"
  value       = aws_iam_role.github_actions_plan.arn
}

output "apply_role_arn" {
  description = "IAM role ARN for terraform apply (read-write, used on main only)"
  value       = aws_iam_role.github_actions_apply.arn
}

output "oidc_provider_arn" {
  description = "GitHub OIDC provider ARN"
  value       = aws_iam_openid_connect_provider.github.arn
}
