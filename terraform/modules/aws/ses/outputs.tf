# Output TXT Record for SES Verification
output "ses_verification_record" {
  value = {
    name  = "_amazonses.${var.domain_name}"
    type  = "TXT"
    value = aws_ses_domain_identity.this.verification_token
  }
}

# Output CNAME Records for DKIM
output "dkim_records" {
  value = [for d in aws_ses_domain_dkim.this.dkim_tokens :
    {
      name  = "${d}._domainkey.${var.domain_name}"
      type  = "CNAME"
      value = "${d}.dkim.amazonses.com"
    }
  ]
}

# Output SPF Record (You should add this to Cloudflare)
output "spf_record" {
  value = {
    name  = var.domain_name
    type  = "TXT"
    value = "v=spf1 include:amazonses.com ~all"
  }
}

# Output MAIL FROM MX Record
output "mail_from_mx_record" {
  value = {
    name  = "mail.${var.domain_name}"
    type  = "MX"
    value = "10 feedback-smtp.${var.domain_name}.amazonses.com"
  }
}

# Output MAIL FROM SPF Record
output "mail_from_spf_record" {
  value = {
    name  = "mail.${var.domain_name}"
    type  = "TXT"
    value = "v=spf1 include:amazonses.com -all"
  }
}
