# Cloud Infrastructure

Various collections of my Terraform configurations across Cloud providers.

The focus is on free or near-free services, I'm cheap.

## Manual Adding Secrets

```bash
# Ran from terraform/ directory in repo root
$ gh secret set TFVARS_CLOUDS_GCP_IAM < clouds/gcp/iam/terraform.tfvars
$ gh secret set TFVARS_CLOUDS_GCP_AUTH_COLINBRUNER_COM < clouds/gcp/auth.colinbruner.com/terraform.tfvars
$ gh secret set TFVARS_PLATFORMS_SUPABASE < platforms/supabase/terraform.tfvars
$ gh secret set TFVARS_CLOUDS_CLOUDFLARE_ZONE_COLINBRUNER.COM < clouds/cloudflare/zone/colinbruner.com/terraform.tfvars
$ gh secret set TFVARS_CLOUDS_CLOUDFLARE_ZERO_TRUST < clouds/cloudflare/zero-trust/terraform.tfvars
```
