# ansible/proxmox

Ansible automation for Proxmox VE hosts. Covers cluster upgrades, TLS certificate provisioning via Let's Encrypt, and OIDC authentication via Pocket ID.

## Directory Structure

```
ansible/proxmox/
├── inventory/
│   ├── hosts.yml                        # Proxmox hosts + SSH user
│   └── host_vars/
│       ├── proxmox-1.yml                # acme_domain: pve1.colinbruner.com
│       ├── proxmox-2.yml                # acme_domain: pve2.colinbruner.com
│       └── proxmox-3.yml                # acme_domain: pve3.colinbruner.com
├── roles/
│   └── proxmox/
│       ├── defaults/main.yml            # Default variables
│       └── tasks/
│           ├── main.yml                 # Imports acme + oidc tasks
│           ├── acme.yml                 # Let's Encrypt cert provisioning
│           └── oidc.yml                 # Pocket ID OIDC realm config
├── configure.yml                        # Main configuration playbook
├── configure.sh                         # Runner — pulls secrets from 1Password
├── upgrade-8to9.yml                     # Cluster upgrade playbook (PVE 8 → 9)
└── upgrade.sh                           # Runner for upgrade playbook
```

## Inventory

| Host | IP | ACME Domain |
|---|---|---|
| proxmox-1 | 192.168.10.11 | pve1.colinbruner.com |
| proxmox-2 | 192.168.10.12 | pve2.colinbruner.com |
| proxmox-3 | 192.168.10.13 | pve3.colinbruner.com |

All hosts connect as `root` via SSH.

---

## configure.yml — Host Configuration

Runs the `proxmox` role across all nodes (serial: 1). Currently covers ACME cert provisioning and OIDC realm setup.

```bash
./configure.sh                   # full configuration
./configure.sh --tags acme       # TLS certificates only
./configure.sh --tags oidc       # OIDC realm only
```

### Secrets (via 1Password)

`configure.sh` reads the following from `op`:

| `op://` path | Variable | Purpose |
|---|---|---|
| `op://lab/cloudflare-proxmox/acme-token` | `cloudflare_token` | Cloudflare API token for DNS-01 |
| `op://lab/cloudflare-proxmox/account-id` | `cloudflare_account_id` | Cloudflare account ID |
| `op://lab/cloudflare-proxmox/acme-email` | `acme_contact` | Let's Encrypt contact email |
| `op://lab/pocket-id-proxmox/issuer-url` | `oidc_issuer_url` | Pocket ID base URL |
| `op://lab/pocket-id-proxmox/client-id` | `oidc_client_id` | OIDC client ID |
| `op://lab/pocket-id-proxmox/client-secret` | `oidc_client_secret` | OIDC client secret |

### ACME / Let's Encrypt (`acme.yml`)

Provisions a valid TLS certificate on each node using Let's Encrypt via Cloudflare DNS-01 challenge. No inbound port exposure required.

**Cluster-level** (run once, stored in `/etc/pve/`):
1. Registers a Let's Encrypt ACME account
2. Configures the Cloudflare DNS plugin (`cf`)

**Per-node:**
1. Sets `acmedomain0` on the node to `pveN.colinbruner.com`
2. Orders the certificate via `pvenode acme cert order`

Proxmox handles automatic renewal (checks daily, renews when < 30 days remain).

**Pre-requisite:** DNS A records must exist in Cloudflare before running:

| Record | Type | Value | Proxy |
|---|---|---|---|
| pve1.colinbruner.com | A | 192.168.10.11 | DNS Only |
| pve2.colinbruner.com | A | 192.168.10.12 | DNS Only |
| pve3.colinbruner.com | A | 192.168.10.13 | DNS Only |

**Cloudflare token permissions required:**
- Zone / DNS / Edit — scoped to `colinbruner.com`

### OIDC / Pocket ID (`oidc.yml`)

Configures a Proxmox OpenID Connect authentication realm backed by Pocket ID. The realm is cluster-wide (stored in `/etc/pve/`) so `run_once` is used.

**Pre-requisite:** Create an OIDC application in Pocket ID with the following redirect URI (no trailing slash):
```
https://pve.colinbruner.com
```

Ensure the `admin` group is listed as an allowed group on the Pocket ID application.

**Key defaults** (set in `roles/proxmox/defaults/main.yml`):

| Variable | Default | Description |
|---|---|---|
| `oidc_realm_name` | `pocket-id` | Proxmox realm identifier — users appear as `user@pocket-id` |
| `oidc_username_claim` | `preferred_username` | OIDC claim used as Proxmox username |
| `oidc_scopes` | `openid email profile groups` | Scopes requested — `openid` is required for ID token |
| `oidc_groups_claim` | `groups` | OIDC claim read for group membership |
| `oidc_autocreate` | `true` | Auto-create users on first login |

**Known limitation — groups not auto-assigned (PVE 9)**

Proxmox's `groups-claim` reads the groups from the ID token but does not persist group membership in the user database in PVE 9. Users are auto-created on first login but land with no group or role.

Workaround — manually assign the user to the `admin` group after their first login:
```bash
pveum user modify <username>@pocket-id --groups admin
```

The `admin` group already has `Administrator` role at `/` via ACL, so this is all that is needed.

---

## upgrade-8to9.yml — Cluster Upgrade

Upgrades Proxmox VE nodes from 8.3 → 8.4 → 9.x one node at a time (`serial: 1`) to preserve cluster quorum.

```bash
./upgrade.sh                     # full upgrade
./upgrade.sh --tags preflight    # pre-flight checks only
./upgrade.sh --tags pve84        # upgrade to PVE 8.4 only
./upgrade.sh --tags pve9         # upgrade to PVE 9 only (requires 8.4 first)
```

### Plays

| Tag | Play | What it does |
|---|---|---|
| `preflight` | Pre-flight checks | Checks PVE version, disk space (≥ 5GB), cluster quorum, runs `pve8to9` checker |
| `pve84` | Upgrade to PVE 8.4 | Disables enterprise repos, adds no-subscription repo (bookworm), dist-upgrades, reboots, verifies |
| `pve9` | Upgrade to PVE 9 | Removes enterprise repos, switches apt sources to trixie, dist-upgrades, reboots into PVE 9 kernel, verifies |
