# ansible/lb

Ansible automation for a **Caddy reverse proxy** running on a Raspberry Pi. Handles installation, TLS certificate provisioning via Cloudflare DNS-01, and OIDC authentication via Pocket ID.

Intended to run on the `dns-lb` image produced by `build/rpi/`.

## Directory Structure

```
ansible/lb/
├── rpi-lb.yml                       # Main playbook
├── install.sh                       # Runner — pulls secrets from 1Password
├── ansible.cfg
└── roles/rpi-lb/
    ├── defaults/main.yml            # Default variables (backends, caddy version, domains)
    ├── handlers/main.yml            # reload/restart caddy, reload systemd
    └── tasks/
        ├── main.yml                 # Task order: install → configure
        ├── install.yml              # Install Docker + Caddy (base + plugin build)
        └── configure.yml            # Template Caddyfile, env file, systemd drop-in
```

## Run

```bash
# Against a specific host
./install.sh 192.168.10.x
```

`install.sh` connects as `pi` and reads all secrets from 1Password.

### Secrets (via 1Password)

| `op://` path | Variable | Purpose |
|---|---|---|
| `op://lab/cloudflare-proxmox/acme-token` | `cloudflare_api_token` | Cloudflare DNS-01 token for TLS cert provisioning |
| `op://lab/test/client-id` | `pocket_id_client_id` | Pocket ID OIDC client ID |
| `op://lab/test/client-secret` | `pocket_id_client_secret` | Pocket ID OIDC client secret |
| `op://lab/caddy-lb/key` | `caddy_auth_key` | JWT signing key for Caddy auth cookies (32+ chars) |

## What Ansible Manages

### Install (`install.yml`)

- **Docker** — installed via `get.docker.com` convenience script (idempotent via `creates:`)
- **Caddy** — base package installed from the official apt repo; then replaced with a custom plugin build from `caddyserver.com/api/download` containing:
  - `caddy-dns/cloudflare` — DNS-01 TLS challenge support
  - `greenpau/caddy-security` — OIDC authentication portal

The `dns-lb` image pre-installs Docker and the Caddy base package at build time. Ansible handles the plugin build replacement and keeps the version pinned via `caddy_version`.

### Configure (`configure.yml`)

Templates the Caddyfile and environment file, then applies `caddy fmt` before deployment to ensure the config is always valid:

1. Template `Caddyfile.j2` → `/etc/caddy/Caddyfile.staged`
2. Run `caddy fmt --overwrite` on the staged file
3. Copy staged → `/etc/caddy/Caddyfile` (checksum-gated — only updates and reloads Caddy when content actually changes)

Environment file (`/etc/caddy/caddy.env`) is loaded via a systemd drop-in at `/etc/systemd/system/caddy.service.d/env.conf`.

## Backends

Configured in `defaults/main.yml` under `caddy_backends`. Each backend is OIDC-protected by default.

| Name | FQDN | Upstream | OIDC |
|---|---|---|---|
| truenas | `truenas.colinbruner.com` | `https://192.168.10.50` | Yes (TLS verify disabled) |

To add a backend, append to `caddy_backends` in `defaults/main.yml`:

```yaml
caddy_backends:
  - name: myservice
    fqdn: "myservice.{{ caddy_base_domain }}"
    upstream: "http://192.168.10.x:port"
    oidc_protected: true
    tls_skip_verify: false
```

## OIDC Configuration

The auth portal lives at `lb.colinbruner.com`. Register the following redirect URI in Pocket ID before running the playbook:

```
https://lb.colinbruner.com/auth/oauth2/pocket-id/authorization-code-callback
```

## Key Variables

| Variable | Default | Description |
|---|---|---|
| `caddy_version` | `v2.9.1` | Pinned Caddy version — update in `defaults/main.yml` |
| `caddy_arch` | `arm64` | Target architecture |
| `caddy_base_domain` | `colinbruner.com` | Base domain for all FQDNs |
| `caddy_auth_fqdn` | `lb.colinbruner.com` | Auth portal hostname |
| `pocket_id_issuer_url` | `https://auth.colinbruner.com` | Pocket ID OIDC issuer |
