
# Allow SES to send email on behalf of colinbruner.com
# NOTE: need to manually add these records to Cloudflare
module "email_notifications" {
  source      = "../../modules/aws/ses"
  domain_name = "colinbruner.com"
}
