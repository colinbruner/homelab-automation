output "ses_dns_records" {
  description = "DNS records to add to Cloudflare for SES domain verification"
  value       = module.ses
}

output "iam_access_key_id" {
  description = "AWS_ACCESS_KEY_ID for the cronhealth poller"
  value       = aws_iam_access_key.cronhealth_poller.id
}

output "iam_secret_access_key" {
  description = "AWS_SECRET_ACCESS_KEY for the cronhealth poller"
  value       = aws_iam_access_key.cronhealth_poller.secret
  sensitive   = true
}
