# Setup order

1. Get the callback URL first — you need it before creating the Pocket ID client:
   https://<cloudflare_team_name>.cloudflareaccess.com/cdn-cgi/access/callback

2. In Pocket ID (https://auth.colinbruner.com → Settings → OIDC Clients):

- Create a new client
- Set the redirect URI to the callback URL above
- Copy the Client ID and Client Secret

3. Create terraform.tfvars:

```hcl
# export TF_VAR_cloudflare_api_token=$(op read "op://core/Cloudflare/API Token - Terraform")
# cloudflare_api_token = "..." # Account:Zero Trust:Edit permission

cloudflare_account_id = "<account-id>"
cloudflare_team_name = "<your-team-name>"
pocket_id_app_url = "https://auth.colinbruner.com"
client_id = "<from Pocket ID>"
client_secret = "<from Pocket ID>"
```

4. terraform init && terraform apply
