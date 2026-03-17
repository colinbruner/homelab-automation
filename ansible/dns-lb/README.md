# ansible/dns-lb

Ansible automation for the **DNS + load balancer** Raspberry Pi servers. Manages both roles in a single playbook — Technitium DNS and Caddy reverse proxy — intended to run on the `dns-lb` image produced by `build/rpi/`.

Two servers are planned for DNS redundancy. Run this playbook against each independently.

## Directory Structure

```
ansible/dns-lb/
├── dns-lb.yml                       # Combined playbook (dns + lb roles)
├── install.sh                       # Runner — pulls all secrets from 1Password
├── ansible.cfg
└── roles/
    ├── dns/                         # Technitium DNS role
    │   ├── defaults/main.yml        # NFS, backup, and Technitium defaults
    │   ├── handlers/main.yml
    │   └── tasks/
    │       ├── main.yml             # Task order: user → install → backup
    │       ├── user.yml             # Create pi user, sudo, SSH key
    │       ├── install.yml          # Install/upgrade Technitium
    │       └── backup.yml           # NFS mount, backup script, systemd timer
    └── rpi-lb/                      # Caddy reverse proxy role
        ├── defaults/main.yml        # Backends, Caddy version, domain config
        ├── handlers/main.yml        # reload/restart caddy, reload systemd
        └── tasks/
            ├── main.yml             # Task order: install → configure
            ├── install.yml          # Install Docker + Caddy (base + plugin build)
            └── configure.yml        # Template Caddyfile, env file, systemd drop-in
```

## Inventory

Hosts are defined in `inv`. Add or remove servers there.

```ini
[dns_lb]
192.168.1.3

[dns_lb:vars]
ansible_user=pi
```

## Run

```bash
# Full run
./install.sh

# DNS role only
./install.sh --tags dns

# LB role only
./install.sh --tags lb

# Dry run
./install.sh --check
```

`install.sh` targets all hosts in `inv` and reads all secrets from 1Password.

## Secrets (via 1Password)

| `op://` path | Variable | Purpose |
|---|---|---|
| `op://private/Personal Key/public key` | `pi_ssh_pubkey` | SSH public key authorized for the `pi` user |
| `op://lab/cloudflare-proxmox/acme-token` | `cloudflare_api_token` | Cloudflare DNS-01 token for TLS cert provisioning |
| `op://lab/test/client-id` | `pocket_id_client_id` | Pocket ID OIDC client ID |
| `op://lab/test/client-secret` | `pocket_id_client_secret` | Pocket ID OIDC client secret |
| `op://lab/caddy-lb/key` | `caddy_auth_key` | JWT signing key for Caddy auth cookies (32+ chars) |
| `op://lab/technitium/password` | `technitium_admin_password` | Technitium DNS admin password (set manually on first login) |

---

## DNS Role (`roles/dns/`)

### User (`user.yml`)

Creates a `pi` user with passwordless sudo and the SSH public key from 1Password. The `dns-lb` image already has the `pi` user from pi-gen — this task is idempotent and ensures the correct key and sudo config are in place.

### Technitium DNS (`install.yml`)

Installs or upgrades Technitium via the official install script. The `dns-lb` image pre-installs Technitium at build time; Ansible re-runs the script on each playbook run to pick up upgrades.

- Install script: `https://download.technitium.com/dns/install.sh`
- Data directory: `/etc/dns`
- Service: `dns` (enabled, started)

Technitium zones, forwarders, and clustering are configured through the web UI (port 5380) or API — not managed by Ansible.

### Backup (`backup.yml`)

Mounts an NFS share and runs a nightly backup of `/etc/dns/` to the NAS.

| Variable | Default | Description |
|---|---|---|
| `nfs_server` | `192.168.10.5` | NFS server address |
| `nfs_export` | `/var/nfs/shared/homelab` | NFS export path |
| `nfs_mount_point` | `/mnt/backup/homelab` | Local mount point |
| `backup_retain_days` | `7` | Days to retain backup archives |
| `backup_schedule` | `02:00:00` | Nightly backup time (systemd OnCalendar) |

Backups are written to `<nfs_mount_point>/dns/`:
- `latest/` — rsync mirror of `/etc/dns/` (always current)
- `dns-backup-YYYYMMDD-HHMMSS.tar.gz` — dated archives, retained for 7 days

### Clustering

Technitium supports multi-primary clustering natively. After both servers are provisioned, configure replication through the Technitium web UI on each node.

---

## LB Role (`roles/rpi-lb/`)

### Install (`install.yml`)

- **Docker** — installed via `get.docker.com` convenience script
- **Caddy** — base package from the official apt repo, then replaced with a custom plugin build containing:
  - `caddy-dns/cloudflare` — DNS-01 TLS challenge support
  - `greenpau/caddy-security` — OIDC authentication portal

The `dns-lb` image pre-installs Docker and the Caddy base package at build time. Ansible handles the plugin build replacement and keeps the version pinned via `caddy_version`.

### Configure (`configure.yml`)

Templates the Caddyfile and environment file, applying `caddy fmt` before deployment:

1. Template `Caddyfile.j2` → `/etc/caddy/Caddyfile.staged`
2. Run `caddy fmt --overwrite` on the staged file
3. Copy staged → `/etc/caddy/Caddyfile` (checksum-gated — only reloads Caddy when content actually changes)

Environment file (`/etc/caddy/caddy.env`) is loaded via a systemd drop-in at `/etc/systemd/system/caddy.service.d/env.conf`.

### Backends

Configured in `roles/rpi-lb/defaults/main.yml` under `caddy_backends`.

| Name | FQDN | Upstream | OIDC |
|---|---|---|---|
| truenas | `truenas.colinbruner.com` | `https://192.168.10.50` | Yes (TLS verify disabled) |

To add a backend:
```yaml
caddy_backends:
  - name: myservice
    fqdn: "myservice.{{ caddy_base_domain }}"
    upstream: "http://192.168.10.x:port"
    oidc_protected: true
    tls_skip_verify: false
```

### OIDC Configuration

The auth portal lives at `lb.colinbruner.com`. Register the following redirect URI in Pocket ID before running the playbook:

```
https://lb.colinbruner.com/auth/oauth2/pocket-id/authorization-code-callback
```

### Key Variables

| Variable | Default | Description |
|---|---|---|
| `caddy_version` | `v2.9.1` | Pinned Caddy version — update in `defaults/main.yml` |
| `caddy_arch` | `arm64` | Target architecture |
| `caddy_base_domain` | `colinbruner.com` | Base domain for all FQDNs |
| `caddy_auth_fqdn` | `lb.colinbruner.com` | Auth portal hostname |
| `pocket_id_issuer_url` | `https://auth.colinbruner.com` | Pocket ID OIDC issuer |
