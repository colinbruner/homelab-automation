# IAM user for the cronhealth poller service
resource "aws_iam_user" "cronhealth_poller" {
  name = "cronhealth-poller"
}

resource "aws_iam_access_key" "cronhealth_poller" {
  user = aws_iam_user.cronhealth_poller.name
}

resource "aws_iam_user_policy" "cronhealth_poller" {
  name = "cronhealth-poller-notifications"
  user = aws_iam_user.cronhealth_poller.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ses:SendEmail"]
        Resource = module.ses.domain_identity_arn
      },
      {
        # SNS direct SMS requires Resource = "*" (no topic ARN)
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = "*"
      }
    ]
  })
}
