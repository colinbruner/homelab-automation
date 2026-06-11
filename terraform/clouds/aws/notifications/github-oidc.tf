###
# GitHub OIDC provider and the role Terraform CI assumes (ADR 0001).
# This lives here because notifications is currently the only AWS workspace;
# split into a dedicated iam workspace if more appear.
###

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # AWS validates GitHub's cert chain against its own trust store for this
  # issuer; the thumbprint is required by the API but effectively unused.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "gha_terraform" {
  name = "gha-terraform"

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
            # PR plans need credentials too (provider refresh), so trust the
            # whole repo rather than only refs/heads/main.
            "token.actions.githubusercontent.com:sub" = "repo:colinbruner/homelab-automation:*"
          }
        }
      }
    ]
  })
}

# This workspace manages IAM users and policies, so PowerUserAccess is not
# sufficient. Single-purpose homelab account; tighten if the account grows.
resource "aws_iam_role_policy_attachment" "gha_terraform" {
  role       = aws_iam_role.gha_terraform.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

output "gha_terraform_role_arn" {
  description = "Set as AWS_TERRAFORM_ROLE_ARN GitHub Actions variable"
  value       = aws_iam_role.gha_terraform.arn
}
