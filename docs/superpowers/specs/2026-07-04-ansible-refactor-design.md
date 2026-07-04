# Ansible Refactor & Scheduled Apply — Design

**Date:** 2026-07-04
**Status:** Approved
**Scope:** `ansible/` directory of `colinbruner/homelab-automation`, plus Semaphore integration requirements (manifests implemented separately in `colinbruner/homelab-k8s`).

## Problem

The `ansible/` directory holds four self-contained mini-projects (`dns-lb`, `pxe`, `warp-connector`, `proxmox`) with no shared conventions:

- Three inventory styles (INI file, YAML dir, ad-hoc `-i "IP,"`), two `ansible.cfg`s, two `requirements/collections.yml`s, connection users scattered across flags/inventory/scripts.
- Entry points vary: `install.sh`, `configure.sh`, `assess.sh`, `upgrade.sh`, a Makefile, raw playbooks.
- Real duplication: the `pvesh … | python3` JSON snippet appears 6× verbatim; APT repo + GPG setup duplicated in `rpi-lb` and `warp-connector`; NFS mount logic duplicated in `dns` and `pxe`; handlers re-declared per role; three roles define an unprefixed `packages` var (collision hazard).
- Everything applies manually; secrets flow through `op` CLI in wrapper scripts as `--extra-vars`.
- No linting or CI.

## Goals

1. One consistent Ansible project: single inventory, config, requirements, and roles directory; roles called intentionally per system.
2. DRY: shared behavior extracted to parametrized roles or replaced by builtin modules.
3. Scheduled, unattended apply of **config playbooks only** via Semaphore UI; provisioning actions stay manual.
4. Secrets resolved at runtime from the existing in-cluster 1Password Connect server — no wrapper scripts, no secrets on CLI args.
5. CI gates (lint + syntax check) on PRs, since `main` becomes live.

## Decisions (with rationale)

| Decision | Choice | Why |
|---|---|---|
| What auto-applies | Config playbooks only (`site.yml`); ops playbooks manual-only | `provision-worker.yml` creates VMs; not desired-state |
| Secrets backend | Existing 1Password Connect (in homelab k8s) | LAN-local, already running, no rate limits; only bootstrap credential is a vault-scoped Connect token |
| Scheduler | Semaphore UI | Purpose-built scheduled-playbook UI; preferred over self-hosted GHA runner |
| Semaphore hosting | k8s via ArgoCD; manifests in `colinbruner/homelab-k8s` | Sits next to Connect; existing GitOps flow |
| Layout | Single project layout (not a collection, not per-service dirs) | One inventory/config/roles dir with least ceremony; the shape Semaphore points at |
| Secret flow | `community.general.onepassword` lookup in `group_vars`, Connect via `OP_CONNECT_HOST`/`OP_CONNECT_TOKEN` env vars | Same code path locally and in Semaphore; wrappers deleted; lazy resolution keeps lint/syntax-check offline |

## Target layout

```
ansible/
├── ansible.cfg              # merged: host_key_checking off, ControlMaster off,
│                            #   roles_path=roles, default inventory, posix deprecation suppression
├── requirements.yml         # ansible.posix, community.general
├── inventory/
│   ├── hosts.yml            # groups: proxmox, dns_lb, pxe, warp
│   ├── group_vars/
│   │   ├── all.yml
│   │   ├── proxmox.yml      # ansible_user: root; proxmox secrets lookups
│   │   ├── dns_lb.yml       # ansible_user: pi; technitium/caddy secrets lookups
│   │   ├── pxe.yml          # ansible_user: root (existing TODO to change later)
│   │   └── warp.yml         # ansible_user: pi; warp token lookup
│   └── host_vars/           # ns1.yml, ns2.yml (cert domains), proxmox-1..3.yml (acme_domain)
├── playbooks/
│   ├── site.yml             # imports the four config playbooks
│   ├── dns-lb.yml
│   ├── pxe.yml
│   ├── warp-connector.yml
│   ├── proxmox.yml          # was configure.yml
│   └── ops/                 # manual-only, never scheduled
│       ├── provision-worker.yml
│       ├── capacity-report.yml
│       └── download-talos.yml   # replaces Makefile ad-hoc target
├── roles/
│   ├── technitium/          # was dns-lb/roles/dns (minus user.yml, backup NFS mount)
│   ├── caddy_lb/            # was dns-lb/roles/rpi-lb
│   ├── pxe/                 # minus NFS mount tasks
│   ├── warp_connector/      # was warp-connector/roles/warp-connector
│   ├── proxmox/             # acme.yml + oidc.yml, unchanged scope
│   ├── proxmox_facts/       # NEW shared: pvesh JSON gathering
│   ├── proxmox_worker/      # NEW: VM-creation logic from provision-worker.yml
│   ├── nfs_mount/           # NEW shared: parametrized NFS mount (+ optional subdirs)
│   └── lab_user/            # NEW shared: user + SSH key + passwordless sudo
└── scripts/
    ├── provision-pxe-lxc.sh # was pxe/provision.sh (pct-based, stays a script)
    └── create-lxc.sh
```

Deleted: all `install.sh` / `configure.sh` / `assess.sh` / `upgrade.sh` wrappers, the pxe `Makefile`, per-dir `ansible.cfg` and `requirements/`, `pxe/roles/pxe/templates/pxelinux.cfg/` (unreferenced), `pxe/roles/pxe/tests/` boilerplate. `upgrade.sh` references `upgrade-8to9.yml` which does not exist in the repo — the script is dead and is removed without replacement.

`README.md` gets a run-book table mapping every old command to its new equivalent.

## Inventory design

Named hosts with `ansible_host`, connection users in `group_vars`:

- `proxmox`: proxmox-1 (192.168.10.11), proxmox-2 (.12), proxmox-3 (.13) — user root
- `dns_lb`: ns1 (192.168.1.3), ns2 (192.168.1.4) — user pi
- `pxe`: pxe-server (192.168.10.4) — user root
- `warp`: warp-connector host — user pi (**IP to confirm during implementation**; currently passed as CLI arg)

Current `host_vars/192.168.1.x.yml` migrate to `host_vars/ns1.yml`/`ns2.yml`.

## Roles: renames, extraction, fixes

**Renames:** `dns` → `technitium`, `rpi-lb` → `caddy_lb`, `warp-connector` → `warp_connector`. Role name = the thing it manages; underscores per Ansible naming rules.

**New shared roles:**

- `nfs_mount` — vars: server, export, mountpoint, mount opts, list of subdirectories (each with mode). Replaces `dns/tasks/backup.yml` mount tasks and `pxe/tasks/mount.yml`. Both call it from their playbook with their own params; role installs `nfs-common`.
- `lab_user` — vars: username, ssh pubkey(s), shell, sudo (bool). From `dns/tasks/user.yml`. Applied in `site.yml` to all hosts needing the `pi` login and, later, to distribute the `semaphore` runner key.
- `proxmox_facts` — var: list of pvesh endpoints to fetch (`status`, `qemu`, `lxc`, `storage`); sets facts `node_<endpoint>`. Replaces the 6× duplicated shell+python snippet in `capacity.yml` and `provision-worker.yml`.
- `proxmox_worker` — the validation + storage-selection + `qm create` logic from `provision-worker.yml`; ops playbook becomes thin (facts role + worker role).

**Builtin replacements:** the curl-pipe-gpg + apt source file tasks in `caddy_lb` and `warp_connector` are replaced with `ansible.builtin.deb822_repository` (one idempotent module for key + repo; removes the `update apt cache` handler dance; needs `python3-debian` package).

**Consistency & correctness:**

- Every role var prefixed with role name (`pxe_packages`, `warp_connector_packages`, `caddy_lb_packages`, …). Enforced by ansible-lint `var-naming[no-role-prefix]`.
- `warp_connector` idempotency: query `warp-cli` registration/connection state and skip `connector new` / `connect` when already registered/connected. Required before scheduled runs.
- File modes normalized to quoted 4-digit octal (`"0644"`).
- `no_log: true` restored/added on secret-touching tasks (several commented out in `technitium/configure.yml`).
- `changed_when`/`failed_when` audited on command/shell/uri tasks.
- The `dns-lb.yml` python3 bootstrap `raw` pre-task is retained in the dns-lb playbook.
- Known quirk preserved as-is: `technitium_cert_pfx_password` defaults to empty (empty-password PFX).

## Secrets

Secret-valued vars live in `group_vars`, resolved lazily by `community.general.onepassword` lookup against Connect (`OP_CONNECT_HOST` / `OP_CONNECT_TOKEN` env vars). Locally, the two env vars are exported (token retrievable via desktop `op` / direnv — the one place `op` CLI remains). In Semaphore they come from a Variable Group backed by a k8s Secret.

Full inventory of current `op://` reads and their destinations:

| Current `op://` path | Was consumed by | New home |
|---|---|---|
| `op://lab/technitium/password` | dns-lb/install.sh → `technitium_admin_password` | lookup in `group_vars/dns_lb.yml` |
| `op://lab/cloudflare-proxmox/acme-token` | dns-lb/install.sh → `cloudflare_api_token`; proxmox/configure.sh → `cloudflare_token` | lookups in `group_vars/dns_lb.yml` and `group_vars/proxmox.yml` |
| `op://lab/caddy-lb/client-id` / `client-secret` / `key` | dns-lb/install.sh → `pocket_id_client_id` / `pocket_id_client_secret` / `caddy_auth_key` | lookups in `group_vars/dns_lb.yml` |
| `op://lab/cloudflare-warp-connector/token` | warp-connector/install.sh → `warp_connector_token` | lookup in `group_vars/warp.yml` |
| `op://lab/cloudflare-proxmox/account-id` / `acme-email` | proxmox/configure.sh → `cloudflare_account_id` / `acme_contact` | lookups in `group_vars/proxmox.yml` |
| `op://lab/pocket-id-proxmox/issuer-url` / `client-id` / `client-secret` | proxmox/configure.sh → `oidc_*` | lookups in `group_vars/proxmox.yml` |
| `op://private/Personal Key/public key` | dns-lb/install.sh → `pi_ssh_pubkey`; pxe/provision.sh | **Plain text in `group_vars/all.yml`** — it is a public key, not a secret, and the Connect token is scoped to the `lab` vault (cannot read `private`) |
| `op://homelab/LXC PXE/password` | pxe/provision.sh (stays a script) | unchanged — script still uses desktop `op` |

Constraint this preserves: lint and `--syntax-check` never need Connect access (lookups resolve only when a play consumes them).

## Semaphore integration

Semaphore is deployed by ArgoCD from `colinbruner/homelab-k8s` (out of scope here). This repo ships `docs/semaphore.md`, a copy-paste runbook for that work, covering:

**Manifest requirements (homelab-k8s side):** official Semaphore image; persistence (BoltDB volume is sufficient); `OP_CONNECT_HOST`/`OP_CONNECT_TOKEN` env from a k8s Secret (Connect is in-cluster — cluster-local service URL); network reach from pods to 192.168.1.x and 192.168.10.x (verify early); GitHub deploy key or PAT to clone this repo.

**In-Semaphore configuration:**

- Key Store: dedicated `semaphore` ed25519 keypair; pubkey distributed to all targets via `lab_user`.
- Repository: this repo, branch `main`, path `ansible/`; Semaphore auto-installs `requirements.yml` collections.
- Task templates: one per config playbook + `site.yml`; ops playbooks get templates for one-click manual runs, **no schedule**.
- Schedules: `site.yml` weekly (Sunday 04:00). First month also runs a mid-week `site.yml --check --diff` drift-report template (delete once trusted). Weekly over nightly: hosts change rarely; smaller unattended blast radius beats convergence latency.
- Notifications on failed tasks (channel chosen at setup).

Consequence: **`main` is live** — merges apply to the lab within the week. CI gates below are therefore load-bearing.

(Design details also captured in Claude memory `semaphore-setup.md` for the homelab-k8s session; `docs/semaphore.md` is canonical.)

## CI / linting

- GitHub Actions on cloud-hosted runners (free; never touch the LAN): `ansible-lint` (includes yamllint) + `ansible-playbook --syntax-check` for every playbook, on PRs touching `ansible/`.
- `.ansible-lint` at repo root, `production` profile. `var-naming[no-role-prefix]` is enabled in PR 2 alongside the prefixing work (it would fail against the as-moved roles in PR 1). Existing violations fixed as they're encountered so CI stays green — no skip-list.
- Docs updated to match reality: `CLAUDE.md` (currently documents old layout in detail), root `README.md`, new `docs/semaphore.md`.

## Migration plan (phased PRs)

Each PR leaves the lab working. Verification per service: `--check --diff` against real hosts before merge; real apply after merge; **second apply must report zero changes** (idempotency proof that scheduled applies depend on).

1. **PR 1 — Scaffold + CI:** new layout with roles moved and renamed (contents unchanged); merged inventory/cfg/requirements; wrappers and Makefile deleted; lint config + GH Actions + lint fixes; README run-book (old → new commands). Behavior-preserving.
2. **PR 2 — DRY refactor:** shared roles (`nfs_mount`, `lab_user`, `proxmox_facts`, `proxmox_worker`); `deb822_repository` conversion; variable prefixing (and enabling the `var-naming[no-role-prefix]` lint rule, deferred from PR 1); warp idempotency fix; dead-code removal.
3. **PR 3 — Secrets:** `op://` table above → lookups in `group_vars`; Connect env docs; `no_log` audit.
4. **PR 4 — Semaphore wiring:** `docs/semaphore.md` finalized; `lab_user` distributes `semaphore` key; templates/schedules configured in the UI (manifest work proceeds in homelab-k8s).

## Risks

- **PXE server** is the riskiest target: a bad apply breaks *cluster rebuilds*, not the running cluster. Its changes get the most careful `--check` review.
- Semaphore pods must reach both LAN subnets; verify before PR 4 (fallback: expose Connect + run Semaphore elsewhere, or hostNetwork).
- The warp host IP is undocumented (CLI arg today); must be recovered from shell history/DHCP before the inventory is complete.
- Until PR 4, everything runs manually exactly as today, just from new paths.

## Out of scope

- Semaphore k8s manifests (homelab-k8s repo, separate session).
- `build/` directory, Terraform, `ansible/proxmox/TODO.md` items not touched by the refactor.
- Changing pxe connection user from root (existing TODO, tracked but not done here).
- Molecule/container-based role testing — lint + check-mode + idempotency verification against real hosts is the chosen level.
