# Create SES Domain Identity
resource "aws_ses_domain_identity" "this" {
  domain = var.domain_name
}

# Enable DKIM Signing
resource "aws_ses_domain_dkim" "this" {
  domain = aws_ses_domain_identity.this.domain
}

# Set up Custom MAIL FROM Domain
resource "aws_ses_domain_mail_from" "this" {
  domain           = aws_ses_domain_identity.this.domain
  mail_from_domain = "mail.${var.domain_name}"
}
