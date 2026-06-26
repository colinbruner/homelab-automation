# Cloudflare DNS Module + colinbruner.com Zone Config

**Date:** 2026-06-26
**Status:** Approved

## Goal

Manage internal Cloudflare A records as Terraform-as-code. Replace the
previous Crossplane-managed records (extracted into `dns-records.yaml`) with a
reusable Terraform module driven by a `hostname → [IPs]` YAML map.

These are `*-internal.colinbruner.com` A records pointing at LAN load-balancer
IPs (192.168.10.x). They are **DNS-only** (grey cloud) — Cloudflare cannot
proxy RFC1918 addresses.

## Decisions

- **Structure:** reusable module + root config (matches existing
  `terraform/modules/` + `terraform/clouds/` split).
- **Provider:** latest stable Cloudflare provider, `~> 5`. Note v5 renamed the
  resource to `cloudflare_dns_record`, requires `name` as an FQDN, and makes
  `ttl` a required argument.
- **Migration:** greenfield create — records do not yet exist in Cloudflare (or
  are removed from Crossplane first). No `terraform import` needed.
- **Proxy/TTL:** `proxied = false`, `ttl = 1` (automatic).
- **YAML location:** moved into the root config dir so the config is
  self-contained.

## Component 1 — Module: `terraform/modules/cloudflare/dns/`

**Purpose:** Given a zone and a `hostname → [IPs]` map, create one A record per
`(hostname, IP)` pair. A hostname with N IPs yields N A records (round-robin).

### Variables (`variables.tf`)

| Variable | Type | Default | Notes |
|---|---|---|---|
| `zone_id` | string | — (required) | Cloudflare zone ID |
| `zone_name` | string | — (required) | e.g. `colinbruner.com`; used to build the FQDN (v5 requires it) |
| `records` | map(list(string)) | — (required) | hostname → list of IPv4 addresses |
| `proxied` | bool | `false` | DNS-only; must be false for RFC1918 IPs |
| `ttl` | number | `1` | `1` = automatic |
| `comment` | string | `"Managed by Terraform (homelab-automation)"` | |

### Logic (`main.tf`)

Flatten the map into stable `for_each` keys (`"<hostname>/<ip>"`) and create one
record each. The FQDN is `${hostname}.${zone_name}`, with `@`/apex mapping to
`zone_name`.

```hcl
locals {
  flattened_records = merge([
    for hostname, ips in var.records : {
      for ip in ips : "${hostname}/${ip}" => { hostname = hostname, ip = ip }
    }
  ]...)
}

resource "cloudflare_dns_record" "this" {
  for_each = local.flattened_records
  zone_id  = var.zone_id
  name     = each.value.hostname == "@" ? var.zone_name : "${each.value.hostname}.${var.zone_name}"
  type     = "A"
  content  = each.value.ip
  ttl      = var.ttl
  proxied  = var.proxied
  comment  = var.comment
}
```

### Outputs (`outputs.tf`)

- `record_ids` — map of `"<hostname>/<ip>"` → record ID.
- `fqdns` — sorted list of created record names.

### Other files

- `versions.tf` — `required_version >= 1.5`, `cloudflare/cloudflare ~> 5`.
- `README.md` — usage example.

## Component 2 — Root config: `terraform/clouds/cloudflare/zone/colinbruner.com/`

| File | Contents |
|---|---|
| `backend.tf` | GCS bucket `bruner-infra`, prefix `clouds/cloudflare/zone/colinbruner.com/` |
| `versions.tf` | `cloudflare ~> 5`, `required_version >= 1.5` |
| `providers.tf` | `provider "cloudflare" { api_token = var.cloudflare_api_token }` |
| `variables.tf` | `cloudflare_api_token` (sensitive), `cloudflare_zone_id`, `cloudflare_domain` (default `colinbruner.com`) |
| `terraform.tfvars` | gitignored; `op read` comment for the token + `cloudflare_zone_id` |
| `dns-records.yaml` | moved here from repo root |
| `main.tf` | `yamldecode` the YAML, call the module |
| `outputs.tf` | pass through `fqdns` / `record_ids` |
| `README.md` | apply instructions |

### `main.tf`

```hcl
locals { dns = yamldecode(file("${path.module}/dns-records.yaml")) }

module "internal_dns" {
  source    = "../../../../modules/cloudflare/dns"
  zone_id   = var.cloudflare_zone_id
  zone_name = var.cloudflare_domain
  records   = local.dns.dns_records
}
```

## Data flow

`dns-records.yaml` → `yamldecode` → `dns_records` map → module → flatten → 22
`cloudflare_dns_record` resources, all DNS-only with TTL automatic:

- argocd-internal, grafana-internal, prometheus-internal, n8n-internal,
  backups-internal, garage-internal, garage-admin-internal → 3 A records each (21)
- sftp-internal → 1 A record (1)

## Verification

No Terraform test framework in this repo. Verify with:

1. `terraform fmt -check -recursive`
2. `terraform init` (module + root)
3. `terraform validate`
4. `terraform plan` against the live zone — confirm **22 to add, 0 to
   change/destroy**.

Steps 3–4 require the Cloudflare API token (via 1Password) and GCS backend
access.
