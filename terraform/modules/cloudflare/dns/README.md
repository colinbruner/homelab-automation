# cloudflare/dns

Creates Cloudflare A records from a `hostname → [IPs]` map. Each `(hostname, IP)`
pair becomes one A record, so a hostname with multiple IPs produces round-robin
records.

Uses the v5 Cloudflare provider (`cloudflare_dns_record`), which requires the
record `name` to be a fully-qualified domain — the module builds it from
`zone_name`.

## Usage

```hcl
module "internal_dns" {
  source = "../../modules/cloudflare/dns"

  zone_id   = var.cloudflare_zone_id
  zone_name = "colinbruner.com"

  records = {
    argocd-internal = ["192.168.10.240", "192.168.10.241", "192.168.10.242"]
    sftp-internal   = ["192.168.10.241"]
  }

  # Defaults: proxied = false, ttl = 1 (automatic)
}
```

Use `"@"` as the hostname for an apex record.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `zone_id` | `string` | — | Cloudflare zone ID |
| `zone_name` | `string` | — | Zone apex domain, used to build each FQDN |
| `records` | `map(list(string))` | — | hostname → list of IPv4 addresses |
| `proxied` | `bool` | `false` | Proxy (orange cloud); must be false for private IPs |
| `ttl` | `number` | `1` | TTL in seconds (`1` = automatic) |
| `comment` | `string` | `"Managed by Terraform (homelab-automation)"` | Per-record comment |

## Outputs

| Name | Description |
|---|---|
| `record_ids` | Map of `"<hostname>/<ip>"` → record ID |
| `fqdns` | Sorted list of created record names |
