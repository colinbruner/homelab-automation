# NOT CURRENTLY ACTIVE
The initial work is done on this, but need to look closer at which records I actually need.

# Email Notifications

This enables SES to send mail on behalf of the `colinbruner.com` domain.

Planning to use this for homelab monitoring...

## Manual

The Terraform will create the necessary resources within AWS but the following outputs must be manually added to Cloudflare - since their TF provider isn't great.
