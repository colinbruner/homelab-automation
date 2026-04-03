# SES domain identity, DKIM, and MAIL FROM
module "ses" {
  source               = "../../../modules/aws/ses"
  domain_name          = var.domain_name
  mail_from_subdomain = var.mail_from_subdomain
}

# SNS SMS preferences
#resource "aws_sns_sms_preferences" "this" {
#  default_sms_type    = "Transactional"
#  monthly_spend_limit = var.sns_monthly_spend_limit
#}
