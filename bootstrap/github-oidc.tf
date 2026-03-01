# GitHub Actions OIDC: Identity Provider + IAM Roles
#
# WHY TWO ROLES:
#
# Since mvaleed/cloud-infra is a PUBLIC repo, we follow the principle of least
# privilege with two separate roles:
#
#   1. "plan" role: Read-only. Used during PR checks to run `terraform plan`.
#
#   2. "apply" role: Read-write. Used on merge to main to run `terraform apply`.
#                    Locked to ONLY ref:refs/heads/main.


# OIDC Identity Provider
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # See: https://github.blog/changelog/2023-07-13-github-actions-oidc-integration-with-aws-no-longer-requires-pinning-of-intermediate-tls-certificates/
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Description = "GitHub Actions OIDC provider for keyless authentication"
  }
}


# Terraform Plan Role (Read-Only)
resource "aws_iam_role" "github_actions_plan" {
  name        = "github-actions-terraform-plan-role"
  description = "Read-only role for terraform plan on PRs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              "repo:${var.github_repo}:ref:refs/heads/*",
              "repo:${var.github_repo}:pull_request"
            ]
          }
        }
      }
    ]
  })

  max_session_duration = 3600

  tags = {
    Role    = "plan"
    Purpose = "CI read-only terraform plan"
  }
}

# Plan role permissions: read-only across AWS + read state from S3
resource "aws_iam_role_policy" "plan_state_access" {
  name = "terraform-state-read"
  role = aws_iam_role.github_actions_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowStateBucketList"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
        ]
        Resource = aws_s3_bucket.terraform_state.arn
      },
      {
        Sid    = "AllowStateRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
        ]
        Resource = "${aws_s3_bucket.terraform_state.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.github_actions_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}


# Terraform Apply Role (Read-Write)
resource "aws_iam_role" "github_actions_apply" {
  name        = "github-actions-terraform-apply-role"
  description = "Read-write role for terraform apply on main"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            # EXACT match on main branch — this is StringEquals, NOT StringLike.
            # No wildcards. Only merges/pushes to main can assume this role.
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
          }
        }
      }
    ]
  })

  max_session_duration = 3600

  tags = {
    Role    = "apply"
    Purpose = "CI terraform apply on main branch only"
  }
}

# TODO: Replace this with a scoped policy once infra stabilizes.
resource "aws_iam_role_policy_attachment" "apply_power_user" {
  role       = aws_iam_role.github_actions_apply.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy" "apply_iam_permissions" {
  name = "terraform-iam-management"
  role = aws_iam_role.github_actions_apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyBootstrapModification"
        Effect = "Deny"
        Action = "iam:*"
        Resource = [
          "arn:aws:iam::${local.account_id}:role/github-actions-*",
          "arn:aws:iam::${local.account_id}:policy/github-actions-*",
          "arn:aws:iam::${local.account_id}:instance-profile/github-actions-*",
          aws_iam_openid_connect_provider.github.arn,
        ]
      },

      {
        Sid    = "AllowIAMManagement"
        Effect = "Allow"
        Action = [
          # Role management
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:UpdateRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:ListRoleTags",
          "iam:PassRole",
          "iam:UpdateAssumeRolePolicy",

          # Policy management
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:TagPolicy",

          # Attaching policies to roles
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:GetRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:ListRolePolicies",

          # Instance profiles
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:ListInstanceProfilesForRole",

          # Service-linked roles (some AWS services require these)
          "iam:CreateServiceLinkedRole",
          "iam:DeleteServiceLinkedRole",
          "iam:GetServiceLinkedRoleDeletionStatus",
        ]
        Resource = "*"
      },

      {
        Sid    = "AllowIAMReadAll"
        Effect = "Allow"
        Action = [
          "iam:ListRoles",
          "iam:ListPolicies",
          "iam:ListInstanceProfiles",
          "iam:ListOpenIDConnectProviders",
          "iam:GetOpenIDConnectProvider",
        ]
        Resource = "*"
      }
    ]
  })
}
