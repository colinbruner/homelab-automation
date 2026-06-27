# cloudflare / zone / colinbruner.com

Internal DNS records for the `colinbruner.com` zone, driven by
[`dns-records.yaml`](./dns-records.yaml) (`hostname → [IPs]`). These are
DNS-only (grey cloud) A records pointing at LAN load-balancer IPs.

Adding or removing a hostname/IP is a one-line edit to `dns-records.yaml`.

## Apply

```bash
cd terraform/clouds/cloudflare/zone/colinbruner.com

# Token comes from 1Password; tfvars is gitignored.
op read "op://core/Cloudflare/API Token - Terraform"   # paste into terraform.tfvars

terraform init
terraform plan
terraform apply
```

State is stored in GCS (`bruner-infra`, prefix
`clouds/cloudflare/zone/colinbruner.com/`).
