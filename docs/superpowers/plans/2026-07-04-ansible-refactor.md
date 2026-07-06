# Ansible Refactor & Scheduled Apply Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate four independent Ansible mini-projects into one standard-layout project with shared roles, 1Password Connect secret lookups, CI lint gates, and Semaphore-ready scheduled apply.

**Architecture:** Single Ansible project at `ansible/` (one inventory/config/requirements, `playbooks/` + `playbooks/ops/`, flat `roles/`). Shared behavior extracted to parametrized roles (`nfs_mount`, `lab_user`, `proxmox_facts`, `proxmox_worker`). Secrets resolve lazily via `community.general.onepassword` lookup against the in-cluster 1Password Connect server. Work is 4 stacked phases, each ending in a PR.

**Tech Stack:** ansible-core 2.21 (local, homebrew), ansible-lint (via `pipx run`), collections `ansible.posix` + `community.general`, GitHub Actions, 1Password Connect, Semaphore UI.

**Spec:** `docs/superpowers/specs/2026-07-04-ansible-refactor-design.md`

## Global Constraints

- LF line endings everywhere (user global rule).
- File modes in Ansible always quoted 4-digit octal strings: `"0644"`, never `644` or `"644"`.
- No secrets in the repo, ever — secret values only via `op` wrapper (Phases 1–2) or onepassword lookups (Phase 3+). SSH **public** keys are fine in plain text.
- Every commit must pass: `cd ansible && pipx run ansible-lint` (expected: `Passed: 0 failure(s), 0 warning(s)`) and syntax-check of all playbooks (command in Task 1 Step 6).
- Commit after every task; branch per phase; PR per phase. Commit messages end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- **Never apply playbooks to live hosts from a task.** Applies/`--check` runs against real infra are user-gated checkpoints at phase boundaries.
- Role variables defined in a role's `defaults/` or `vars/` must be prefixed with the role name (enforced by lint from Task 13 on). Vars supplied from `group_vars`/playbooks (e.g. `cloudflare_api_token`, `talos_linux_version`, `workers`) stay unprefixed.
- `hosts:` in playbooks always names an inventory group (`proxmox`, `dns_lb`, `pxe`, `warp`) — never `all`.

---

## Phase 1 — Scaffold + CI (branch `refactor/ansible-layout`, PR 1)

Behavior-preserving restructure. Role contents unchanged except paths/names.

### Task 1: Project config + lint + CI workflow

**Files:**
- Create: `ansible/ansible.cfg`, `ansible/requirements.yml`, `.ansible-lint`, `.github/workflows/ansible-lint.yml`
- Branch: `git checkout -b refactor/ansible-layout` (from `main`)

**Interfaces:**
- Produces: `ansible/` is the project root — all later `ansible-playbook`/`ansible-lint` commands run from it; `roles_path=roles`, default inventory `inventory/hosts.yml`.

- [ ] **Step 1: Create branch**

```bash
git checkout main && git pull && git checkout -b refactor/ansible-layout
```

- [ ] **Step 2: Write `ansible/ansible.cfg`** (merge of the two existing cfgs + project defaults)

```ini
[defaults]
inventory = inventory/hosts.yml
roles_path = roles
host_key_checking = False
# Suppress deprecation warnings from ansible.posix collection internals (to_native
# import path). Remove once ansible.posix publishes a fix upstream.
deprecation_warnings = False

[ssh_connection]
ssh_args = -o ControlMaster=no -o ControlPath=none
```

- [ ] **Step 3: Write `ansible/requirements.yml`**

```yaml
---
collections:
  - name: ansible.posix
  - name: community.general
```

- [ ] **Step 4: Write `.ansible-lint`** (repo root)

```yaml
---
profile: production
exclude_paths:
  - .github/
  - build/
  - terraform/
  - docs/
```

- [ ] **Step 5: Write `.github/workflows/ansible-lint.yml`**

```yaml
---
name: ansible-lint
on:
  pull_request:
    paths:
      - "ansible/**"
      - ".ansible-lint"
      - ".github/workflows/ansible-lint.yml"
  push:
    branches: [main]
    paths:
      - "ansible/**"

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run ansible-lint
        uses: ansible/ansible-lint@v25

  syntax-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - name: Install ansible-core
        run: pip install ansible-core
      - name: Syntax check all playbooks
        working-directory: ansible
        run: |
          ansible-galaxy collection install -r requirements.yml
          for pb in playbooks/*.yml playbooks/ops/*.yml; do
            ansible-playbook --syntax-check "$pb"
          done
```

- [ ] **Step 6: Verify lint runs** (no playbooks yet — should pass trivially)

```bash
cd ansible && ansible-galaxy collection install -r requirements.yml && pipx run ansible-lint
```
Expected: `Passed: 0 failure(s), 0 warning(s)` (or "no files found" style success). The syntax-check loop used by later tasks is:
```bash
cd ansible && for pb in playbooks/*.yml playbooks/ops/*.yml; do ansible-playbook --syntax-check "$pb" || exit 1; done
```

- [ ] **Step 7: Commit**

```bash
git add ansible/ansible.cfg ansible/requirements.yml .ansible-lint .github/workflows/ansible-lint.yml
git commit -m "feat: scaffold unified ansible project config + lint CI"
```

### Task 2: Unified inventory

**Files:**
- Create: `ansible/inventory/hosts.yml`, `ansible/inventory/group_vars/{proxmox,dns_lb,pxe,warp}.yml`, `ansible/inventory/host_vars/{ns1,ns2,proxmox-1,proxmox-2,proxmox-3}.yml`
- Delete: `ansible/dns-lb/inv`, `ansible/dns-lb/host_vars/`, `ansible/proxmox/inventory/`

**Interfaces:**
- Produces: groups `proxmox`, `dns_lb`, `pxe`, `warp`; hosts `ns1`, `ns2`, `pxe-server`, `proxmox-1..3`. All later playbooks target these groups. Connection users live here, never in CLI flags.

- [ ] **Step 1: Write `ansible/inventory/hosts.yml`** (warp runs on ns1 — confirmed by user 2026-07-04)

```yaml
---
all:
  children:
    proxmox:
      hosts:
        proxmox-1:
          ansible_host: 192.168.10.11
        proxmox-2:
          ansible_host: 192.168.10.12
        proxmox-3:
          ansible_host: 192.168.10.13
    dns_lb:
      hosts:
        ns1:
          ansible_host: 192.168.1.3
        ns2:
          ansible_host: 192.168.1.4
    pxe:
      hosts:
        pxe-server:
          ansible_host: 192.168.10.4
    warp:
      hosts:
        ns1:
```

- [ ] **Step 2: Write group_vars**

`ansible/inventory/group_vars/proxmox.yml`:
```yaml
---
ansible_user: root
```
`ansible/inventory/group_vars/dns_lb.yml`:
```yaml
---
ansible_user: pi
```
`ansible/inventory/group_vars/pxe.yml` (Talos version consolidated here from `pxe/vars/main.yml` + role vars — both are `v1.12.4` today, so behavior is unchanged; role `vars/main.yml` entry is removed in Step 4):
```yaml
---
# TODO(pre-existing): stop connecting as root (carried over from pxe/install.sh)
ansible_user: root

# The Talos version to download vmlinuz and initramfs from.
# NOTE: old versions will not be automatically cleaned up.
talos_linux_version: v1.12.4
```
`ansible/inventory/group_vars/warp.yml`:
```yaml
---
ansible_user: pi
```

- [ ] **Step 3: Write host_vars** (migrated from `dns-lb/host_vars/192.168.1.{3,4}.yml` and `proxmox/inventory/host_vars/`)

`ansible/inventory/host_vars/ns1.yml`:
```yaml
---
# FQDN for this node's Let's Encrypt certificate.
# Must match the hostname Technitium will use after cluster initialization
# (i.e. <hostname>.<cluster-domain> from the cluster init dialog).
technitium_cert_domain: "ns1.colinbruner.com"
```
`ansible/inventory/host_vars/ns2.yml`: same with `ns2.colinbruner.com`.
`ansible/inventory/host_vars/proxmox-1.yml`:
```yaml
---
acme_domain: pve1.colinbruner.com
```
`proxmox-2.yml` / `proxmox-3.yml`: same with `pve2` / `pve3`.

- [ ] **Step 4: Remove the superseded vars/inventory files**

```bash
git rm ansible/dns-lb/inv ansible/dns-lb/host_vars/192.168.1.3.yml ansible/dns-lb/host_vars/192.168.1.4.yml
git rm -r ansible/proxmox/inventory
git rm ansible/pxe/vars/main.yml
```
Then edit `ansible/pxe/roles/pxe/vars/main.yml`: delete the `talos_linux_version: v1.12.4` line and its two comment lines (now in group_vars); keep `ubuntu_versions` (removed as dead code in Task 8).

- [ ] **Step 5: Verify inventory parses with expected groups**

```bash
cd ansible && ansible-inventory --list | python3 -c "import json,sys; d=json.load(sys.stdin); print(sorted(k for k in d if k not in ('_meta','all')))"
```
Expected: `['dns_lb', 'proxmox', 'pxe', 'warp']`. Also `ansible-inventory --host ns1` must show `ansible_user: pi` and `technitium_cert_domain`.

- [ ] **Step 6: Commit**

```bash
git add -A ansible/inventory && git add -u && git commit -m "feat: unified inventory with proxmox/dns_lb/pxe/warp groups"
```

### Task 3: Move dns-lb (roles technitium + caddy_lb, playbook, wrapper)

**Files:**
- Move: `ansible/dns-lb/roles/dns/` → `ansible/roles/technitium/`; `ansible/dns-lb/roles/rpi-lb/` → `ansible/roles/caddy_lb/`; `ansible/dns-lb/README.md` → `docs/dns-lb.md`; `ansible/dns-lb/CLUSTERING.md` → `docs/dns-lb-clustering.md`
- Create: `ansible/playbooks/dns-lb.yml`, `ansible/scripts/run-dns-lb.sh`
- Delete: `ansible/dns-lb/` (everything remaining: `dns-lb.yml`, `install.sh`, `ansible.cfg`, `requirements/`)

**Interfaces:**
- Produces: roles `technitium`, `caddy_lb`; playbook `playbooks/dns-lb.yml` targeting group `dns_lb`. Wrapper `scripts/run-dns-lb.sh` is temporary (deleted Task 14).

- [ ] **Step 1: Move roles and docs**

```bash
mkdir -p ansible/roles ansible/playbooks ansible/scripts
git mv ansible/dns-lb/roles/dns ansible/roles/technitium
git mv ansible/dns-lb/roles/rpi-lb ansible/roles/caddy_lb
git mv ansible/dns-lb/README.md docs/dns-lb.md
git mv ansible/dns-lb/CLUSTERING.md docs/dns-lb-clustering.md
```

- [ ] **Step 2: Write `ansible/playbooks/dns-lb.yml`** (was `dns-lb/dns-lb.yml`; group + renamed roles + play name)

```yaml
---
- name: Configure DNS + LB raspberry pis
  hosts: dns_lb
  gather_facts: false
  pre_tasks:
    - name: Bootstrap python3
      ansible.builtin.raw: apt-get update && apt-get install -y python3
      become: true
      changed_when: false

    - name: Gather facts
      ansible.builtin.setup:
      become: true

  roles:
    - role: technitium
      become: true
      tags: dns

    - role: caddy_lb
      become: true
      tags: lb
```

- [ ] **Step 3: Write `ansible/scripts/run-dns-lb.sh`** (temporary secrets wrapper, updated paths; mode 0755)

```bash
#!/usr/bin/env bash
set -euo pipefail

# TEMPORARY: deleted in Phase 3 when secrets move to onepassword lookups.
ANSIBLE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

PI_PUBKEY=$(op read "op://private/Personal Key/public key")
CF_TOKEN=$(op read "op://lab/cloudflare-proxmox/acme-token")
POCKET_ID_CLIENT_ID=$(op read "op://lab/caddy-lb/client-id")
POCKET_ID_CLIENT_SECRET=$(op read "op://lab/caddy-lb/client-secret")
CADDY_AUTH_KEY=$(op read "op://lab/caddy-lb/key")
TECHNITIUM_ADMIN_PASSWORD=$(op read "op://lab/technitium/password")

# Write vars to a temp file to avoid shell word-splitting on the SSH key value
TMPVARS=$(mktemp /tmp/ansible-vars-XXXXXX.yml)
trap 'rm -f $TMPVARS' EXIT
printf 'pi_ssh_pubkey: "%s"\n' "$PI_PUBKEY" > "$TMPVARS"

cd "$ANSIBLE_DIR"
ansible-galaxy collection install -r requirements.yml

ansible-playbook \
    --extra-vars "@${TMPVARS}" \
    --extra-vars "cloudflare_api_token=${CF_TOKEN} pocket_id_client_id=${POCKET_ID_CLIENT_ID} pocket_id_client_secret=${POCKET_ID_CLIENT_SECRET} caddy_auth_key=${CADDY_AUTH_KEY} technitium_admin_password=${TECHNITIUM_ADMIN_PASSWORD}" \
    playbooks/dns-lb.yml ${@+"$@"}
```
```bash
chmod 755 ansible/scripts/run-dns-lb.sh
```

- [ ] **Step 4: Delete the rest of dns-lb/**

```bash
git rm ansible/dns-lb/dns-lb.yml ansible/dns-lb/install.sh ansible/dns-lb/ansible.cfg ansible/dns-lb/requirements/collections.yml
```
(`ansible/dns-lb/` must now be empty/gone — verify with `ls ansible/dns-lb 2>&1`.)

- [ ] **Step 5: Fix any lint findings in moved roles** (production profile will flag e.g. unnamed-task or `key=value` style if present). Run:

```bash
cd ansible && pipx run ansible-lint && ansible-playbook --syntax-check playbooks/dns-lb.yml
```
Expected: lint passes, syntax check `playbook: playbooks/dns-lb.yml`. Fix findings mechanically (task naming/casing only — no behavior changes; variable prefixing is Task 13, do NOT do it here).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "refactor: move dns-lb into unified layout (roles technitium, caddy_lb)"
```

### Task 4: Move pxe (role, playbook, ops/download-talos, scripts)

**Files:**
- Move: `ansible/pxe/roles/pxe/` → `ansible/roles/pxe/`; `ansible/pxe/provision.sh` → `ansible/scripts/provision-pxe-lxc.sh`; `ansible/pxe/scripts/create-lxc.sh` → `ansible/scripts/create-lxc.sh`; `ansible/pxe/scripts/download-talos-images.sh` → `ansible/roles/pxe/scripts/download-talos-images.sh`; `ansible/pxe/README.md` → `docs/pxe.md`
- Create: `ansible/playbooks/pxe.yml`, `ansible/playbooks/ops/download-talos.yml`
- Delete: `ansible/pxe/` remainder (`pxe.yml`, `install.sh`, `Makefile`, `requirements/`)

**Interfaces:**
- Produces: role `pxe`; playbooks `playbooks/pxe.yml` (group `pxe`) and `playbooks/ops/download-talos.yml`. Consumes `talos_linux_version` from `group_vars/pxe.yml` (Task 2).

- [ ] **Step 1: Move files**

```bash
mkdir -p ansible/playbooks/ops
git mv ansible/pxe/roles/pxe ansible/roles/pxe
git mv ansible/pxe/provision.sh ansible/scripts/provision-pxe-lxc.sh
git mv ansible/pxe/scripts/create-lxc.sh ansible/scripts/create-lxc.sh
git mv ansible/pxe/scripts/download-talos-images.sh ansible/roles/pxe/scripts/download-talos-images.sh
git mv ansible/pxe/README.md docs/pxe.md
```
Then edit `ansible/scripts/provision-pxe-lxc.sh`: change `scripts/create-lxc.sh` reference to `create-lxc.sh` resolved relative to the script's own dir:
```bash
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ansible "all" -u root -i "$PROXMOX_HOST," -m script -a "$SCRIPT_DIR/create-lxc.sh $ROOTPASS \"$PUBKEY\""
```

- [ ] **Step 2: Write `ansible/playbooks/pxe.yml`**

```yaml
---
- name: Configure PXE boot server
  hosts: pxe
  vars:
    download_images: false # NOTE: Override via -e when refreshing ISO extracts
  roles:
    - role: pxe
      become: true
```

- [ ] **Step 3: Write `ansible/playbooks/ops/download-talos.yml`** (replaces the Makefile `download-talos` ad-hoc target)

```yaml
---
- name: Download Talos boot images to PXE server
  hosts: pxe
  become: true
  vars:
    talos_download_arches:
      - amd64
      - arm64
  tasks:
    - name: Run download script on target (uploaded + cleaned up automatically)
      ansible.builtin.script:
        cmd: >-
          {{ playbook_dir }}/../../roles/pxe/scripts/download-talos-images.sh
          {{ talos_linux_version }} {{ talos_download_arches | join(' ') }}
      register: pxe_talos_download
      changed_when: "'downloaded' in pxe_talos_download.stdout | lower"
```
Note: check `ansible/roles/pxe/scripts/download-talos-images.sh` output — if it doesn't print anything containing "downloaded" on change, set `changed_when: true` instead and note it in the commit body.

- [ ] **Step 4: Delete pxe/ remainder**

```bash
git rm ansible/pxe/pxe.yml ansible/pxe/install.sh ansible/pxe/Makefile ansible/pxe/requirements/collections.yml
```

- [ ] **Step 5: Lint + syntax check, fix mechanically** (same rules as Task 3 Step 5)

```bash
cd ansible && pipx run ansible-lint && ansible-playbook --syntax-check playbooks/pxe.yml && ansible-playbook --syntax-check playbooks/ops/download-talos.yml
```

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "refactor: move pxe into unified layout; ops/download-talos replaces Makefile"
```

### Task 5: Move warp-connector

**Files:**
- Move: `ansible/warp-connector/roles/warp-connector/` → `ansible/roles/warp_connector/`
- Create: `ansible/playbooks/warp-connector.yml`, `ansible/scripts/run-warp-connector.sh`
- Delete: `ansible/warp-connector/` remainder (`warp-connector.yml`, `install.sh`, `ansible.cfg`)

**Interfaces:**
- Produces: role `warp_connector`; playbook `playbooks/warp-connector.yml` targeting group `warp`.

- [ ] **Step 1: Move role**

```bash
git mv ansible/warp-connector/roles/warp-connector ansible/roles/warp_connector
```

- [ ] **Step 2: Write `ansible/playbooks/warp-connector.yml`**

```yaml
---
- name: Configure Cloudflare WARP connector
  hosts: warp
  roles:
    - role: warp_connector
      become: true
```

- [ ] **Step 3: Write `ansible/scripts/run-warp-connector.sh`** (mode 0755)

```bash
#!/usr/bin/env bash
set -euo pipefail

# TEMPORARY: deleted in Phase 3 when secrets move to onepassword lookups.
ANSIBLE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

# Token from Cloudflare Zero Trust > Networks > WARP Connector.
WARP_TOKEN=$(op read "op://lab/cloudflare-warp-connector/token")

cd "$ANSIBLE_DIR"
ansible-playbook \
    --extra-vars "warp_connector_token=${WARP_TOKEN}" \
    playbooks/warp-connector.yml ${@+"$@"}
```

- [ ] **Step 4: Delete remainder**

```bash
git rm ansible/warp-connector/warp-connector.yml ansible/warp-connector/install.sh ansible/warp-connector/ansible.cfg
```

- [ ] **Step 5: Lint + syntax check, fix mechanically**

```bash
cd ansible && pipx run ansible-lint && ansible-playbook --syntax-check playbooks/warp-connector.yml
```

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "refactor: move warp-connector into unified layout (role warp_connector)"
```

### Task 6: Move proxmox (role, config playbook, ops playbooks)

**Files:**
- Move: `ansible/proxmox/roles/proxmox/` → `ansible/roles/proxmox/`; `ansible/proxmox/configure.yml` → `ansible/playbooks/proxmox.yml`; `ansible/proxmox/capacity.yml` → `ansible/playbooks/ops/capacity-report.yml`; `ansible/proxmox/provision-worker.yml` → `ansible/playbooks/ops/provision-worker.yml`; `ansible/proxmox/vars/workers.yml` → `ansible/playbooks/ops/vars/workers.yml`; `ansible/proxmox/templates/capacity-report.j2` → `ansible/playbooks/ops/templates/capacity-report.j2`; `ansible/proxmox/README.md` → `docs/proxmox.md`; `ansible/proxmox/TODO.md` → `docs/proxmox-todo.md`
- Create: `ansible/scripts/run-proxmox.sh`
- Delete: `ansible/proxmox/` remainder (`assess.sh`, `configure.sh`, `provision-worker.sh`, `upgrade.sh`)

**Interfaces:**
- Produces: role `proxmox`; playbooks `playbooks/proxmox.yml`, `playbooks/ops/capacity-report.yml`, `playbooks/ops/provision-worker.yml`. Ops playbooks keep their inline tasks until Tasks 10–11.

- [ ] **Step 1: Move files**

```bash
mkdir -p ansible/playbooks/ops/vars ansible/playbooks/ops/templates
git mv ansible/proxmox/roles/proxmox ansible/roles/proxmox
git mv ansible/proxmox/configure.yml ansible/playbooks/proxmox.yml
git mv ansible/proxmox/capacity.yml ansible/playbooks/ops/capacity-report.yml
git mv ansible/proxmox/provision-worker.yml ansible/playbooks/ops/provision-worker.yml
git mv ansible/proxmox/vars/workers.yml ansible/playbooks/ops/vars/workers.yml
git mv ansible/proxmox/templates/capacity-report.j2 ansible/playbooks/ops/templates/capacity-report.j2
git mv ansible/proxmox/README.md docs/proxmox.md
git mv ansible/proxmox/TODO.md docs/proxmox-todo.md
```
Relative `vars_files: vars/workers.yml` and `src: templates/capacity-report.j2` resolve against the playbook dir, so they keep working after the move. Update the usage comment header in `playbooks/proxmox.yml`: replace the `./configure.sh` examples with `./scripts/run-proxmox.sh` / `./scripts/run-proxmox.sh --tags acme`.

- [ ] **Step 2: Write `ansible/scripts/run-proxmox.sh`** (mode 0755)

```bash
#!/usr/bin/env bash
set -euo pipefail

# TEMPORARY: deleted in Phase 3 when secrets move to onepassword lookups.
ANSIBLE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

# Cloudflare credentials (for ACME DNS-01)
CF_TOKEN=$(op read "op://lab/cloudflare-proxmox/acme-token")
CF_ACCOUNT_ID=$(op read "op://lab/cloudflare-proxmox/account-id")
ACME_EMAIL=$(op read "op://lab/cloudflare-proxmox/acme-email")

# Pocket ID OIDC credentials
OIDC_ISSUER_URL=$(op read "op://lab/pocket-id-proxmox/issuer-url")
OIDC_CLIENT_ID=$(op read "op://lab/pocket-id-proxmox/client-id")
OIDC_CLIENT_SECRET=$(op read "op://lab/pocket-id-proxmox/client-secret")

cd "$ANSIBLE_DIR"
ansible-playbook \
    -e "cloudflare_token=${CF_TOKEN}" \
    -e "cloudflare_account_id=${CF_ACCOUNT_ID}" \
    -e "acme_contact=${ACME_EMAIL}" \
    -e "oidc_issuer_url=${OIDC_ISSUER_URL}" \
    -e "oidc_client_id=${OIDC_CLIENT_ID}" \
    -e "oidc_client_secret=${OIDC_CLIENT_SECRET}" \
    "$@" \
    playbooks/proxmox.yml
```

- [ ] **Step 3: Delete dead/trivial wrappers**

```bash
git rm ansible/proxmox/assess.sh ansible/proxmox/configure.sh ansible/proxmox/provision-worker.sh ansible/proxmox/upgrade.sh
```
(`upgrade.sh` references `upgrade-8to9.yml` which does not exist — dead. `assess.sh`/`provision-worker.sh` are one-liners replaced by direct `ansible-playbook` commands, documented in Task 7's README.)

- [ ] **Step 4: Lint + syntax check all three playbooks, fix mechanically**

```bash
cd ansible && pipx run ansible-lint \
  && ansible-playbook --syntax-check playbooks/proxmox.yml \
  && ansible-playbook --syntax-check playbooks/ops/capacity-report.yml \
  && ansible-playbook --syntax-check playbooks/ops/provision-worker.yml
```

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "refactor: move proxmox into unified layout; ops playbooks split out"
```

### Task 7: site.yml, README run-book, CLAUDE.md, PR 1

**Files:**
- Create: `ansible/playbooks/site.yml`
- Modify: `README.md` (Repository Structure + usage sections), `CLAUDE.md` (Directory Structure, Common Tasks, Important Files sections)

**Interfaces:**
- Produces: `playbooks/site.yml` — the single converge-everything entry point Semaphore schedules in Phase 4.

- [ ] **Step 1: Write `ansible/playbooks/site.yml`**

```yaml
---
# Converge all lab config. Scheduled weekly by Semaphore (see docs/semaphore.md).
# Ops playbooks (playbooks/ops/) are intentionally NOT imported — manual only.
- name: Import proxmox configuration
  ansible.builtin.import_playbook: proxmox.yml

- name: Import dns + lb configuration
  ansible.builtin.import_playbook: dns-lb.yml

- name: Import pxe server configuration
  ansible.builtin.import_playbook: pxe.yml

- name: Import warp connector configuration
  ansible.builtin.import_playbook: warp-connector.yml
```
Note: until Phase 3, `site.yml` full runs need the secrets the wrappers supply — document in README that `site.yml` becomes directly runnable in Phase 3. It must still syntax-check now.

- [ ] **Step 2: Update `README.md`** — replace the `ansible/` portion of the Repository Structure tree with the new layout (copy the tree from the spec's "Target layout" section) and add this run-book section:

```markdown
## Running playbooks

All commands run from `ansible/` (`cd ansible`). One-time: `ansible-galaxy collection install -r requirements.yml`.

| Old command | New command |
|---|---|
| `ansible/dns-lb/install.sh` | `./scripts/run-dns-lb.sh` (until secrets migration: direct `ansible-playbook playbooks/dns-lb.yml`) |
| `ansible/pxe/install.sh <ip>` | `ansible-playbook playbooks/pxe.yml` |
| `ansible/pxe/Makefile download-talos` | `ansible-playbook playbooks/ops/download-talos.yml` |
| `ansible/pxe/provision.sh <proxmox-ip>` | `ansible/scripts/provision-pxe-lxc.sh <proxmox-ip>` |
| `ansible/warp-connector/install.sh <ip>` | `./scripts/run-warp-connector.sh` |
| `ansible/proxmox/configure.sh` | `./scripts/run-proxmox.sh` |
| `ansible/proxmox/assess.sh` | `ansible-playbook playbooks/ops/capacity-report.yml` |
| `ansible/proxmox/provision-worker.sh` | `ansible-playbook playbooks/ops/provision-worker.yml` |
| (new) converge everything | `ansible-playbook playbooks/site.yml` |
```

- [ ] **Step 3: Update `CLAUDE.md`** — rewrite the `Directory Structure`, `Common Tasks`, and `Important Files` sections to match the new layout (paths: `ansible/playbooks/…`, `ansible/roles/…`, `ansible/inventory/…`, `ansible/scripts/…`; Talos version now lives in `ansible/inventory/group_vars/pxe.yml`; note `playbooks/ops/` is manual-only). Keep all non-ansible sections untouched.

- [ ] **Step 4: Full verification**

```bash
cd ansible && pipx run ansible-lint && for pb in playbooks/*.yml playbooks/ops/*.yml; do ansible-playbook --syntax-check "$pb" || exit 1; done
ls ansible/dns-lb ansible/pxe ansible/warp-connector ansible/proxmox 2>&1
```
Expected: lint + syntax pass; the four old dirs no longer exist.

- [ ] **Step 5: Commit + open PR 1**

```bash
git add -A && git commit -m "feat: add site.yml; update README run-book and CLAUDE.md for new layout"
git push -u origin refactor/ansible-layout
gh pr create --title "refactor: unified ansible project layout + lint CI" --body "PR 1 of 4 (spec: docs/superpowers/specs/2026-07-04-ansible-refactor-design.md). Behavior-preserving restructure; see README run-book for old->new commands.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

**CHECKPOINT (user):** verify with `--check --diff` per service via the wrappers / direct commands before merging; after merge, real apply + confirm a second apply reports zero changes. Phase 2 branches from this work.

---

## Phase 2 — DRY refactor (branch `refactor/ansible-dry`, PR 2)

Branch from `refactor/ansible-layout` (or `main` if PR 1 merged).

### Task 8: Dead code removal + mode normalization

**Files:**
- Delete: `ansible/roles/pxe/templates/pxelinux.cfg/` (unreferenced by any task), `ansible/roles/pxe/tests/`, `ansible/roles/pxe/meta/main.yml` (galaxy boilerplate, no real deps)
- Modify: `ansible/roles/pxe/vars/main.yml` (delete — `ubuntu_versions` is referenced by no task; verify first), `ansible/roles/pxe/tasks/*.yml` (modes)

- [ ] **Step 1: Verify deadness, then delete**

```bash
grep -rn "pxelinux" ansible/roles ansible/playbooks   # expect: no task/template references (only the dir itself)
grep -rn "ubuntu_versions" ansible/roles ansible/playbooks   # expect: only the vars/main.yml definition
git rm -r ansible/roles/pxe/templates/pxelinux.cfg ansible/roles/pxe/tests ansible/roles/pxe/meta
git rm ansible/roles/pxe/vars/main.yml
```
If either grep shows a real consumer, keep that file and note it in the commit body instead.

- [ ] **Step 2: Normalize modes in pxe role** — in `ansible/roles/pxe/tasks/configure.yml`, `mount.yml`, `talos.yml`: replace every `mode: "644"` with `mode: "0644"` and `mode: "755"` with `mode: "0755"`.

```bash
grep -rn 'mode: "[0-9]\{3\}"' ansible/roles/   # expect: no output when done
```

- [ ] **Step 3: Lint + syntax check + commit**

```bash
cd ansible && pipx run ansible-lint && for pb in playbooks/*.yml playbooks/ops/*.yml; do ansible-playbook --syntax-check "$pb" || exit 1; done
git add -A && git commit -m "refactor: remove dead pxe role content; normalize file modes"
```

### Task 9: nfs_mount shared role

**Files:**
- Create: `ansible/roles/nfs_mount/defaults/main.yml`, `ansible/roles/nfs_mount/tasks/main.yml`
- Modify: `ansible/roles/technitium/tasks/backup.yml`, `ansible/roles/pxe/tasks/mount.yml`, `ansible/roles/pxe/defaults/main.yml`

**Interfaces:**
- Produces: role `nfs_mount` with vars `nfs_mount_server`, `nfs_mount_export`, `nfs_mount_point`, `nfs_mount_opts` (default `"rw,sync,hard"`), `nfs_mount_boot` (default `true`), `nfs_mount_mode` (default `"0755"`), `nfs_mount_subdirs` (list of `{path, mode}` relative to mount point, default `[]`). Invoked via `ansible.builtin.include_role` from consumer roles.

- [ ] **Step 1: Write `ansible/roles/nfs_mount/defaults/main.yml`**

```yaml
---
nfs_mount_server: ""
nfs_mount_export: ""
nfs_mount_point: ""
nfs_mount_opts: "rw,sync,hard"
# Whether to mount at boot (writes fstab 'auto'); pxe historically used boot: false
nfs_mount_boot: true
nfs_mount_mode: "0755"
# Subdirectories to create under the mount point: [{path: "pxe/tftp", mode: "0755"}]
nfs_mount_subdirs: []
```

- [ ] **Step 2: Write `ansible/roles/nfs_mount/tasks/main.yml`**

```yaml
---
- name: Install nfs client packages
  ansible.builtin.apt:
    pkg:
      - nfs-common
    state: present

- name: Create mount point
  ansible.builtin.file:
    path: "{{ nfs_mount_point }}"
    state: directory
    mode: "{{ nfs_mount_mode }}"

- name: Mount nfs share
  ansible.posix.mount:
    src: "{{ nfs_mount_server }}:{{ nfs_mount_export }}"
    path: "{{ nfs_mount_point }}"
    fstype: nfs
    opts: "{{ nfs_mount_opts }}"
    boot: "{{ nfs_mount_boot }}"
    state: mounted

- name: Create subdirectories on mount
  ansible.builtin.file:
    path: "{{ nfs_mount_point }}/{{ item.path }}"
    state: directory
    mode: "{{ item.mode | default('0755') }}"
  loop: "{{ nfs_mount_subdirs }}"
```

- [ ] **Step 3: Refactor `ansible/roles/technitium/tasks/backup.yml`** — replace the first five tasks (install nfs client packages / check if nfs already mounted / create nfs mount point / mount nfs backup share / create dns backup subdirectory) with:

```yaml
- name: Install backup prerequisites
  ansible.builtin.apt:
    pkg:
      - rsync
    state: present

- name: Mount nfs backup share
  ansible.builtin.include_role:
    name: nfs_mount
  vars:
    nfs_mount_server: "{{ technitium_backup_nfs_server }}"
    nfs_mount_export: "{{ technitium_backup_nfs_export }}"
    nfs_mount_point: "{{ technitium_backup_mount_point }}"
    nfs_mount_opts: "{{ technitium_backup_mount_opts }}"
    nfs_mount_mode: "0750"
    nfs_mount_subdirs:
      - path: dns
        mode: "0750"
```
Keep the backup script/service/timer tasks unchanged, but they reference `nfs_mount_point` — replace those references with `technitium_backup_mount_point`, and `backup_retain_days`/`backup_schedule` with `technitium_backup_retain_days`/`technitium_backup_schedule`. In `ansible/roles/technitium/defaults/main.yml` rename: `nfs_server`→`technitium_backup_nfs_server`, `nfs_export`→`technitium_backup_nfs_export`, `nfs_mount_point`→`technitium_backup_mount_point`, `nfs_mount_opts`→`technitium_backup_mount_opts`, `backup_retain_days`→`technitium_backup_retain_days`, `backup_schedule`→`technitium_backup_schedule` (same values).

- [ ] **Step 4: Refactor `ansible/roles/pxe/tasks/mount.yml`** to a single include (replaces all three tasks):

```yaml
---
# Mount the NAS images/backup share onto the PXE server and lay out its dirs.
- name: Mount nfs image share
  ansible.builtin.include_role:
    name: nfs_mount
  vars:
    nfs_mount_server: "{{ nfs_server_addr }}"
    nfs_mount_export: "{{ nfs_server_share_path }}"
    nfs_mount_point: "{{ pxe_nfs_share_path }}"
    nfs_mount_boot: false
    nfs_mount_subdirs:
      - path: pxe/tftp
      - path: pxe/tftp/images
      - path: pxe/http
```
In `ansible/roles/pxe/defaults/main.yml`, delete the now-unused `directories:` list (the subdir paths above are the same three, expressed relative to `pxe_nfs_share_path: /srv/backup/homelab`).

- [ ] **Step 5: Verify no orphaned references, lint, syntax, commit**

```bash
grep -rn "nfs_server\b\|nfs_export\b\|backup_retain_days\|backup_schedule\|directories" ansible/roles/technitium ansible/roles/pxe
# expect: only the new technitium_backup_* names and pxe nfs_server_addr/nfs_server_share_path
cd ansible && pipx run ansible-lint && for pb in playbooks/*.yml playbooks/ops/*.yml; do ansible-playbook --syntax-check "$pb" || exit 1; done
git add -A && git commit -m "refactor: extract shared nfs_mount role (technitium backup + pxe)"
```

### Task 10: lab_user shared role

**Files:**
- Create: `ansible/roles/lab_user/defaults/main.yml`, `ansible/roles/lab_user/tasks/main.yml`
- Create: `ansible/inventory/group_vars/all.yml`
- Modify: `ansible/playbooks/dns-lb.yml`
- Delete: `ansible/roles/technitium/tasks/user.yml` (+ its include in `technitium/tasks/main.yml`)

**Interfaces:**
- Produces: role `lab_user` with vars `lab_user_name` (default `pi`), `lab_user_shell` (default `/bin/bash`), `lab_user_sudo` (default `true`), `lab_user_pubkeys` (list, default `[]`). Consumes `lab_authorized_pubkeys` from `group_vars/all.yml`. Phase 4 reuses this role to distribute the Semaphore key to root users.

- [ ] **Step 1: Write `ansible/roles/lab_user/defaults/main.yml`**

```yaml
---
lab_user_name: pi
lab_user_shell: /bin/bash
lab_user_sudo: true
lab_user_pubkeys: []
```

- [ ] **Step 2: Write `ansible/roles/lab_user/tasks/main.yml`** (from technitium `user.yml`, parametrized)

```yaml
---
- name: Install sudo
  ansible.builtin.apt:
    name: sudo
    state: present
  when: lab_user_sudo

- name: Create user
  ansible.builtin.user:
    name: "{{ lab_user_name }}"
    shell: "{{ lab_user_shell }}"
    groups: "{{ ['sudo'] if lab_user_sudo else [] }}"
    append: true
    state: present

- name: Add ssh public keys
  ansible.posix.authorized_key:
    user: "{{ lab_user_name }}"
    key: "{{ item }}"
    state: present
  loop: "{{ lab_user_pubkeys }}"

- name: Allow passwordless sudo
  ansible.builtin.copy:
    dest: "/etc/sudoers.d/{{ lab_user_name }}"
    content: "{{ lab_user_name }} ALL=(ALL) NOPASSWD:ALL\n"
    mode: "0440"
    validate: visudo -cf %s
  when: lab_user_sudo
```

- [ ] **Step 3: Fetch the personal public key and write `ansible/inventory/group_vars/all.yml`**

```bash
op read "op://private/Personal Key/public key"
```
Paste the output (a public key — safe in git) into:
```yaml
---
# SSH public keys authorized on lab hosts (distributed by the lab_user role).
# Public keys are not secrets. The Semaphore runner key is added in Phase 4.
lab_authorized_pubkeys:
  - "<PASTE ACTUAL PUBKEY OUTPUT HERE>"
```
If `op read` fails (no session), STOP and ask the user to run it — do not invent a key.

- [ ] **Step 4: Wire into dns-lb playbook; remove user.yml** — in `ansible/playbooks/dns-lb.yml` add before the technitium role:

```yaml
    - role: lab_user
      become: true
      vars:
        lab_user_pubkeys: "{{ lab_authorized_pubkeys }}"
      tags: user
```
Delete `ansible/roles/technitium/tasks/user.yml` and remove the `- name: user` include block from `ansible/roles/technitium/tasks/main.yml`. Remove `pi_ssh_pubkey` from `ansible/scripts/run-dns-lb.sh` (the `op read`, the TMPVARS block, and the `--extra-vars "@${TMPVARS}"` line).

- [ ] **Step 5: Verify, lint, syntax, commit**

```bash
grep -rn "pi_ssh_pubkey" ansible/    # expect: no output
cd ansible && pipx run ansible-lint && ansible-playbook --syntax-check playbooks/dns-lb.yml
git add -A && git commit -m "refactor: extract lab_user role; personal pubkey to group_vars/all.yml"
```

### Task 11: proxmox_facts shared role + capacity-report refactor

**Files:**
- Create: `ansible/roles/proxmox_facts/defaults/main.yml`, `ansible/roles/proxmox_facts/tasks/main.yml`
- Modify: `ansible/playbooks/ops/capacity-report.yml`

**Interfaces:**
- Produces: role `proxmox_facts`; var `proxmox_facts_endpoints` (list from `status`/`qemu`/`lxc`/`storage`, default `[status]`). Sets host facts named `node_<endpoint>` (e.g. `node_status`) — these exact names are consumed by `capacity-report.j2` (via `hostvars`) and by `proxmox_worker` (Task 12).

- [ ] **Step 1: Write `ansible/roles/proxmox_facts/defaults/main.yml`**

```yaml
---
# Which pvesh node endpoints to fetch: status, qemu, lxc, storage
proxmox_facts_endpoints:
  - status
```

- [ ] **Step 2: Write `ansible/roles/proxmox_facts/tasks/main.yml`** (the shell+python unwrap appears exactly once, here — it previously existed 6x)

```yaml
---
# pvesh sometimes wraps output in {"data": ...} depending on version; the
# python snippet unwraps it so downstream code always sees the bare value.
- name: Get node data via pvesh
  ansible.builtin.shell: |
    set -o pipefail
    pvesh get /nodes/$(hostname -s)/{{ item }} --output-format json \
      | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d.get('data', d) if isinstance(d, dict) else d))"
  args:
    executable: /bin/bash
  loop: "{{ proxmox_facts_endpoints }}"
  register: proxmox_facts_raw
  changed_when: false
  failed_when: proxmox_facts_raw.rc != 0 or proxmox_facts_raw.stdout | length == 0

- name: Set node facts
  ansible.builtin.set_fact:
    "node_{{ item.item }}": "{{ item.stdout | from_json }}"
  loop: "{{ proxmox_facts_raw.results }}"
  loop_control:
    label: "{{ item.item }}"
```

- [ ] **Step 3: Refactor `ansible/playbooks/ops/capacity-report.yml`** — replace the entire first play's `tasks:` (the four `get node …` shell tasks + `set node facts`) with the role; keep the assert and the second (localhost render) play unchanged:

```yaml
---
- name: Gather proxmox node capacity facts
  hosts: proxmox
  gather_facts: false
  vars:
    target_vcpu: 4
    target_ram_gb: 4
    target_disk_gb: 50
    report_output_path: /tmp/proxmox-capacity-report.txt
  roles:
    - role: proxmox_facts
      vars:
        proxmox_facts_endpoints:
          - status
          - qemu
          - lxc
          - storage
  post_tasks:
    - name: Assert node_status has expected fields
      ansible.builtin.assert:
        that:
          - "'cpuinfo' in node_status"
          - "'memory' in node_status"
          - "'loadavg' in node_status"
        fail_msg: >-
          Unexpected node_status structure on {{ inventory_hostname }}.
          Present keys: {{ node_status.keys() | list }}.
          Full value: {{ node_status }}
```

- [ ] **Step 4: Lint, syntax, commit**

```bash
cd ansible && pipx run ansible-lint && ansible-playbook --syntax-check playbooks/ops/capacity-report.yml
git add -A && git commit -m "refactor: extract proxmox_facts role, dedupe pvesh gathering"
```

### Task 12: proxmox_worker role + thin provision-worker playbook

**Files:**
- Create: `ansible/roles/proxmox_worker/defaults/main.yml`, `ansible/roles/proxmox_worker/tasks/main.yml`
- Modify: `ansible/playbooks/ops/provision-worker.yml`

**Interfaces:**
- Consumes: fact `node_storage` set by `proxmox_facts`; per-host var `node_workers` (set via `add_host` in the playbook).
- Produces: role `proxmox_worker` with defaults `proxmox_worker_vcpus: 4`, `proxmox_worker_ram_mb: 4096`, `proxmox_worker_disk_gb: 50`, `proxmox_worker_bridge: vmbr0`, `proxmox_worker_storage: ""`.

- [ ] **Step 1: Write `ansible/roles/proxmox_worker/defaults/main.yml`**

```yaml
---
proxmox_worker_vcpus: 4
proxmox_worker_ram_mb: 4096
proxmox_worker_disk_gb: 50
proxmox_worker_bridge: vmbr0
proxmox_worker_storage: "" # empty = auto-select largest images-capable pool
```

- [ ] **Step 2: Write `ansible/roles/proxmox_worker/tasks/main.yml`** (moved verbatim from the third play of provision-worker.yml, with prefixed defaults)

```yaml
---
- name: Fail if no VM-capable storage pool found
  ansible.builtin.fail:
    msg: >-
      No storage pool with 'images' content found on {{ inventory_hostname }}.
      Available pools: {{ node_storage | map(attribute='storage') | list | join(', ') }}
  when:
    - proxmox_worker_storage == ''
    - node_storage | selectattr('content', 'search', 'images') | list | length == 0

- name: Select default storage pool
  ansible.builtin.set_fact:
    _default_storage: >-
      {{ proxmox_worker_storage if proxmox_worker_storage != ''
         else (node_storage
               | selectattr('content', 'search', 'images')
               | sort(attribute='avail')
               | last).storage }}

- name: Create and start assigned VMs
  ansible.builtin.shell: |
    VMID=$(pvesh get /cluster/nextid)
    STORAGE="{{ item.storage if 'storage' in item and item.storage != '' else _default_storage }}"
    qm create "$VMID" \
      --name "{{ item.name }}" \
      --memory {{ item.ram_mb | default(proxmox_worker_ram_mb) }} \
      --cores {{ item.vcpus | default(proxmox_worker_vcpus) }} \
      --sockets 1 \
      --cpu x86-64-v2-AES \
      --scsihw virtio-scsi-pci \
      --scsi0 "${STORAGE}:{{ item.disk_gb | default(proxmox_worker_disk_gb) }}" \
      --net0 "virtio,bridge={{ item.bridge | default(proxmox_worker_bridge) }}" \
      --boot "order=net0;scsi0" \
      --ostype l26 \
      --agent 1
    qm start "$VMID"
    echo "$VMID"
  register: _vm_create_results
  changed_when: true
  loop: "{{ node_workers }}"
  loop_control:
    label: "{{ item.name }}"

- name: Summarize created VMs
  ansible.builtin.debug:
    msg: "Created '{{ item.item.name }}' → VM ID {{ item.stdout_lines | last | trim }} on {{ inventory_hostname }}"
  loop: "{{ _vm_create_results.results }}"
  loop_control:
    label: "{{ item.item.name }}"
```

- [ ] **Step 3: Thin out `ansible/playbooks/ops/provision-worker.yml`** — plays become: (1) facts via role, (2) validation/add_host unchanged, (3) role call:

Play 1 (replaces the two shell tasks + set_fact):
```yaml
- name: Gather proxmox node capacity facts
  hosts: proxmox
  gather_facts: false
  vars_files:
    - vars/workers.yml
  roles:
    - role: proxmox_facts
      vars:
        proxmox_facts_endpoints:
          - status
          - storage
```
Play 2 (validate config and register target nodes): keep exactly as-is, including its `vars:` block mapping `vm_*` — but delete the `vm_*` entries from that play's `vars:` (they come from `vars/workers.yml`).
Play 3:
```yaml
- name: Create talos worker VMs
  hosts: vm_target
  gather_facts: false
  vars_files:
    - vars/workers.yml
  roles:
    - role: proxmox_worker
      vars:
        proxmox_worker_vcpus: "{{ vm_vcpus }}"
        proxmox_worker_ram_mb: "{{ vm_ram_mb }}"
        proxmox_worker_disk_gb: "{{ vm_disk_gb }}"
        proxmox_worker_bridge: "{{ vm_bridge }}"
        proxmox_worker_storage: "{{ vm_storage }}"
```
(`playbooks/ops/vars/workers.yml` keeps its user-facing `vm_*` names — it's an ops config file, not role internals.)

- [ ] **Step 4: Lint, syntax, commit**

```bash
cd ansible && pipx run ansible-lint && ansible-playbook --syntax-check playbooks/ops/provision-worker.yml
git add -A && git commit -m "refactor: extract proxmox_worker role; thin provision-worker playbook"
```

### Task 13: deb822 apt repos + warp idempotency + var prefixing + lint rule

**Files:**
- Modify: `ansible/roles/caddy_lb/{defaults/main.yml,tasks/install.yml,handlers/main.yml}`, `ansible/roles/warp_connector/{defaults/main.yml,tasks/install.yml,tasks/configure.yml,handlers/main.yml}`, `ansible/roles/pxe/defaults/main.yml` + pxe tasks/templates, `ansible/roles/proxmox/defaults/main.yml` + proxmox tasks, `ansible/roles/technitium/defaults` (already prefixed except done in Task 9), `ansible/scripts/run-proxmox.sh`, `ansible/inventory/host_vars/proxmox-*.yml`, `.ansible-lint`

**Interfaces:**
- Produces: final variable names later phases depend on — notably `proxmox_acme_contact`, `proxmox_cloudflare_token`, `proxmox_cloudflare_account_id`, `proxmox_oidc_issuer_url`, `proxmox_oidc_client_id`, `proxmox_oidc_client_secret`, `proxmox_acme_domain` (host_vars), `warp_connector_token`, `caddy_lb_*`, `pxe_*`. Phase 3 group_vars use these names verbatim.

- [ ] **Step 1: caddy_lb — deb822 conversion.** In `ansible/roles/caddy_lb/tasks/install.yml` replace the `add caddy gpg key`, `add caddy apt repository`, and `flush handlers` tasks with:

```yaml
- name: Add caddy apt repository
  ansible.builtin.deb822_repository:
    name: caddy-stable
    types: [deb]
    uris: https://dl.cloudsmith.io/public/caddy/stable/deb/debian
    suites: any-version
    components: [main]
    signed_by: https://dl.cloudsmith.io/public/caddy/stable/gpg.key
  register: caddy_lb_repo

- name: Update apt cache after repo change
  ansible.builtin.apt:
    update_cache: true
  when: caddy_lb_repo is changed
```
Add `python3-debian` to the role's prerequisite packages list. Remove `caddy_gpg_url`, `caddy_gpg_dest`, `caddy_apt_repo_url`, `caddy_apt_file` from defaults. Remove the now-unused `update apt cache` handler.

- [ ] **Step 2: warp_connector — deb822 conversion.** Same pattern in `ansible/roles/warp_connector/tasks/install.yml`:

```yaml
- name: Add cloudflare warp apt repository
  ansible.builtin.deb822_repository:
    name: cloudflare-warp
    types: [deb]
    uris: https://pkg.cloudflareclient.com/
    suites: "{{ ansible_distribution_release }}"
    components: [main]
    signed_by: https://pkg.cloudflareclient.com/pubkey.gpg
  register: warp_connector_repo

- name: Update apt cache after repo change
  ansible.builtin.apt:
    update_cache: true
  when: warp_connector_repo is changed
```
Add `python3-debian` to prerequisites; remove `warp_gpg_url`/`warp_gpg_dest`/`warp_apt_file` defaults and the `update apt cache` handler.

- [ ] **Step 3: warp_connector — idempotency.** Replace the `register warp connector with cloudflare` and `connect warp` tasks in `tasks/configure.yml` with:

```yaml
- name: Check warp registration
  ansible.builtin.command: warp-cli --accept-tos registration show
  register: warp_connector_registration
  changed_when: false
  failed_when: false

- name: Register warp connector with cloudflare
  ansible.builtin.command:
    cmd: "warp-cli --accept-tos connector new {{ warp_connector_token }}"
  when: warp_connector_registration.rc != 0
  no_log: true

- name: Check warp connection status
  ansible.builtin.command: warp-cli --accept-tos status
  register: warp_connector_status
  changed_when: false

- name: Connect warp
  ansible.builtin.command:
    cmd: warp-cli --accept-tos connect
  when: "'Connected' not in warp_connector_status.stdout"
```
NOTE for the user-run apply: `registration show` exists on current warp-cli; if the deployed version predates it, the check task's `rc != 0` fallback means it re-registers — flag it at the apply checkpoint if `warp-cli --version` is old.

- [ ] **Step 4: Variable prefixing.** Apply these renames — definition + every reference (tasks, templates, playbooks, host_vars, scripts). Method per role: edit defaults, then `grep -rln 'old_name' ansible/ | xargs sed -i '' 's/\bold_name\b/new_name/g'`, then grep to confirm zero old-name hits.

| Role | Old | New |
|---|---|---|
| caddy_lb | `packages` | `caddy_lb_packages` |
| caddy_lb | `caddy_version`, `caddy_arch`, `caddy_download_url`, `caddy_base_domain`, `caddy_auth_fqdn`, `caddy_cookie_domain`, `caddy_backends` | `caddy_lb_version`, `caddy_lb_arch`, `caddy_lb_download_url`, `caddy_lb_base_domain`, `caddy_lb_auth_fqdn`, `caddy_lb_cookie_domain`, `caddy_lb_backends` |
| caddy_lb | `pocket_id_issuer_url` | `caddy_lb_oidc_issuer_url` |
| caddy_lb (runtime, from wrapper) | `pocket_id_client_id`, `pocket_id_client_secret`, `caddy_auth_key` | `caddy_lb_oidc_client_id`, `caddy_lb_oidc_client_secret`, `caddy_lb_auth_key` (update `run-dns-lb.sh` `-e` names too) |
| warp_connector | `packages` | `warp_connector_packages` |
| pxe | `packages`, `ipxe_packages` | `pxe_packages`, `pxe_ipxe_packages` |
| pxe | `ipxe_files_served_by_tftp`, `grub_files_served_by_tftp` | `pxe_ipxe_tftp_files`, `pxe_grub_tftp_files` |
| pxe | `talos_linux_architectures` | `pxe_talos_architectures` |
| pxe | `nfs_server_addr`, `nfs_server_share_path` | `pxe_nfs_server_addr`, `pxe_nfs_export` |
| proxmox | `acme_account_name`, `acme_directory`, `acme_dns_plugin_id`, `acme_dns_plugin`, `acme_domain` | `proxmox_acme_account_name`, `proxmox_acme_directory`, `proxmox_acme_dns_plugin_id`, `proxmox_acme_dns_plugin`, `proxmox_acme_domain` (incl. `host_vars/proxmox-*.yml`) |
| proxmox | `oidc_realm_name`, `oidc_username_claim`, `oidc_scopes`, `oidc_groups_claim`, `oidc_autocreate`, `oidc_default_realm`, `oidc_comment`, `oidc_group_role_mappings` | `proxmox_oidc_` + same suffix |
| proxmox (runtime, from wrapper) | `cloudflare_token`, `cloudflare_account_id`, `acme_contact`, `oidc_issuer_url`, `oidc_client_id`, `oidc_client_secret` | `proxmox_cloudflare_token`, `proxmox_cloudflare_account_id`, `proxmox_acme_contact`, `proxmox_oidc_issuer_url`, `proxmox_oidc_client_id`, `proxmox_oidc_client_secret` (update `run-proxmox.sh` `-e` names too) |

Deliberately unprefixed (shared/playbook-level): `cloudflare_api_token` (used by both technitium + caddy_lb templates), `technitium_*` (already prefixed), `talos_linux_version`, `download_images`, `warp_connector_token` (already prefixed), `lab_authorized_pubkeys`, ops `vm_*`/`workers`/`target_*`/`report_output_path`.

- [ ] **Step 5: Enable the lint rule.** Append to `.ansible-lint`:

```yaml
enable_list:
  - var-naming[no-role-prefix]
```

- [ ] **Step 6: no_log audit.** In `ansible/roles/technitium/tasks/configure.yml`: uncomment/add `no_log: true` on `get current settings`, `enable https on technitium web service`, and the two zone/record tasks IF they interpolate `technitium_token` (they do — all four get `no_log: true`). Check remaining `command`/`shell`/`uri` tasks across all roles: any that interpolate a `*_token`/`*_password`/`*_secret`/`*_key` var must have `no_log: true`.

- [ ] **Step 7: Full lint + syntax + grep sweep, commit**

```bash
grep -rn "pocket_id_\|caddy_auth_key\|acme_contact\b\|cloudflare_token\b\|cloudflare_account_id\b" ansible/ | grep -v proxmox_ | grep -v caddy_lb_
# expect: no output
cd ansible && pipx run ansible-lint && for pb in playbooks/*.yml playbooks/ops/*.yml; do ansible-playbook --syntax-check "$pb" || exit 1; done
git add -A && git commit -m "refactor: deb822 apt repos, warp idempotency, role-prefixed variables"
```

- [ ] **Step 8: Open PR 2**

```bash
git push -u origin refactor/ansible-dry
gh pr create --title "refactor: DRY shared roles, deb822 repos, var prefixing" --body "PR 2 of 4 (spec: docs/superpowers/specs/2026-07-04-ansible-refactor-design.md). New shared roles: nfs_mount, lab_user, proxmox_facts, proxmox_worker.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

**CHECKPOINT (user):** `--check --diff` per service; real apply; second apply must show zero changes (this is the idempotency gate for scheduled applies — especially warp).

---

## Phase 3 — Secrets via 1Password Connect (branch `refactor/ansible-secrets`, PR 3)

### Task 14: Lookup-based secrets, delete wrappers

**Files:**
- Modify: `ansible/inventory/group_vars/{dns_lb,warp,proxmox}.yml`, `README.md`
- Delete: `ansible/scripts/run-dns-lb.sh`, `ansible/scripts/run-warp-connector.sh`, `ansible/scripts/run-proxmox.sh`

**Interfaces:**
- Consumes: variable names finalized in Task 13. `op://<vault>/<item>/<field>` maps to `lookup('community.general.onepassword', '<item>', field='<field>', vault='<vault>')`.
- Produces: playbooks runnable directly with only `OP_CONNECT_HOST`/`OP_CONNECT_TOKEN` exported.

- [ ] **Step 1: Add lookups to `ansible/inventory/group_vars/dns_lb.yml`**

```yaml
---
ansible_user: pi

# Secrets resolve at runtime from 1Password Connect.
# Requires OP_CONNECT_HOST and OP_CONNECT_TOKEN in the environment (see README).
cloudflare_api_token: "{{ lookup('community.general.onepassword', 'cloudflare-proxmox', field='acme-token', vault='lab') }}"
technitium_admin_password: "{{ lookup('community.general.onepassword', 'technitium', field='password', vault='lab') }}"
caddy_lb_oidc_client_id: "{{ lookup('community.general.onepassword', 'caddy-lb', field='client-id', vault='lab') }}"
caddy_lb_oidc_client_secret: "{{ lookup('community.general.onepassword', 'caddy-lb', field='client-secret', vault='lab') }}"
caddy_lb_auth_key: "{{ lookup('community.general.onepassword', 'caddy-lb', field='key', vault='lab') }}"
```

- [ ] **Step 2: `ansible/inventory/group_vars/warp.yml`**

```yaml
---
ansible_user: pi
warp_connector_token: "{{ lookup('community.general.onepassword', 'cloudflare-warp-connector', field='token', vault='lab') }}"
```

- [ ] **Step 3: `ansible/inventory/group_vars/proxmox.yml`**

```yaml
---
ansible_user: root

proxmox_cloudflare_token: "{{ lookup('community.general.onepassword', 'cloudflare-proxmox', field='acme-token', vault='lab') }}"
proxmox_cloudflare_account_id: "{{ lookup('community.general.onepassword', 'cloudflare-proxmox', field='account-id', vault='lab') }}"
proxmox_acme_contact: "{{ lookup('community.general.onepassword', 'cloudflare-proxmox', field='acme-email', vault='lab') }}"
proxmox_oidc_issuer_url: "{{ lookup('community.general.onepassword', 'pocket-id-proxmox', field='issuer-url', vault='lab') }}"
proxmox_oidc_client_id: "{{ lookup('community.general.onepassword', 'pocket-id-proxmox', field='client-id', vault='lab') }}"
proxmox_oidc_client_secret: "{{ lookup('community.general.onepassword', 'pocket-id-proxmox', field='client-secret', vault='lab') }}"
```

- [ ] **Step 4: Delete wrappers; update README**

```bash
git rm ansible/scripts/run-dns-lb.sh ansible/scripts/run-warp-connector.sh ansible/scripts/run-proxmox.sh
```
README: replace the wrapper entries in the run-book table with direct `ansible-playbook playbooks/<name>.yml`, and add:

```markdown
### Secrets

Playbooks resolve secrets at runtime from the in-cluster 1Password Connect server.
Export before running anything that touches secrets:

    export OP_CONNECT_HOST="https://<connect-host>"   # cluster Connect endpoint
    export OP_CONNECT_TOKEN="$(op read 'op://lab/onepassword-connect/token')"

Lint and --syntax-check never need these (lookups are lazy).
```

- [ ] **Step 5: Verify lazy resolution — syntax check WITHOUT the env vars set**

```bash
cd ansible && env -u OP_CONNECT_HOST -u OP_CONNECT_TOKEN sh -c 'for pb in playbooks/*.yml playbooks/ops/*.yml; do ansible-playbook --syntax-check "$pb" || exit 1; done' && pipx run ansible-lint
```
Expected: all pass (proves CI never needs Connect).

- [ ] **Step 6: Commit + PR 3**

```bash
git add -A && git commit -m "feat: resolve secrets via 1Password Connect lookups; remove op wrappers"
git push -u origin refactor/ansible-secrets
gh pr create --title "feat: 1Password Connect secret lookups" --body "PR 3 of 4 (spec: docs/superpowers/specs/2026-07-04-ansible-refactor-design.md). Wrappers deleted; export OP_CONNECT_HOST/OP_CONNECT_TOKEN to run.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

**CHECKPOINT (user):** with Connect env vars exported, `--check` then apply each playbook; confirm each op item/field name matches (typo in an item name = lookup failure at run time, not lint time). NOTE: a Connect *token* for the runner may need creating — 1Password Connect tokens are issued per vault via `op connect token create`.

---

## Phase 4 — Semaphore wiring (branch `feat/semaphore-docs`, PR 4)

### Task 15: Semaphore runbook + runner key distribution

**Files:**
- Create: `docs/semaphore.md`
- Modify: `ansible/inventory/group_vars/all.yml`, `ansible/playbooks/proxmox.yml`, `ansible/playbooks/pxe.yml`, `ansible/playbooks/dns-lb.yml` (comment only), `CLAUDE.md`, `README.md`

**Interfaces:**
- Consumes: `lab_user` role (Task 10), `lab_authorized_pubkeys` (group_vars/all.yml).
- Produces: `docs/semaphore.md` — canonical runbook the homelab-k8s session reads before writing manifests.

- [ ] **Step 1: Generate the Semaphore runner keypair** (user-gated — needs 1Password write):

```bash
ssh-keygen -t ed25519 -N "" -C "semaphore@lab" -f /tmp/semaphore_lab_key
cat /tmp/semaphore_lab_key.pub
```
Ask the user to store the private key as a new 1Password item `op://lab/semaphore-ssh/private-key` (it will be pasted into Semaphore's Key Store, never into the repo), then delete `/tmp/semaphore_lab_key*`. Add the **public** key to `ansible/inventory/group_vars/all.yml`:

```yaml
lab_authorized_pubkeys:
  - "<existing personal pubkey>"
  - "<semaphore pubkey output>"
```

- [ ] **Step 2: Distribute the key to root-login groups** — `lab_user` currently runs only in dns-lb.yml (pi). Add to `ansible/playbooks/proxmox.yml` and `ansible/playbooks/pxe.yml` as the first role:

```yaml
    - role: lab_user
      become: true
      vars:
        lab_user_name: root
        lab_user_shell: /bin/bash
        lab_user_sudo: false
        lab_user_pubkeys: "{{ lab_authorized_pubkeys }}"
      tags: user
```
(For an existing `root` user the user task is a no-op; only `authorized_key` does work. `lab_user_sudo: false` skips the sudo/sudoers tasks.)

- [ ] **Step 3: Write `docs/semaphore.md`** with these sections (full prose, no stubs):
  1. **Purpose** — scheduled applies of `ansible/playbooks/site.yml`; ops playbooks manual-only.
  2. **Deployment (homelab-k8s repo)** — ArgoCD app; official `semaphoreui/semaphore` image; BoltDB on a PVC; env `OP_CONNECT_HOST` (cluster-local Connect service URL) + `OP_CONNECT_TOKEN` from a k8s Secret (token scoped read-only to `lab` vault); pod egress must reach 192.168.1.0/24 and 192.168.10.0/24 (verify with a debug pod before installing); repo access via GitHub deploy key.
  3. **In-Semaphore setup** — Key Store: `semaphore` SSH key (private key from `op://lab/semaphore-ssh/private-key`); Repository: `colinbruner/homelab-automation`, branch `main`, path `ansible/`; Environment: the two Connect env vars; Task templates: `site.yml`, `dns-lb.yml`, `pxe.yml`, `warp-connector.yml`, `proxmox.yml`, plus ops templates `capacity-report.yml`, `provision-worker.yml`, `download-talos.yml` (no schedules on ops).
  4. **Schedules** — `site.yml` weekly Sunday 04:00 (`0 4 * * 0`); first month: additional Wednesday 04:00 template running `site.yml` with `--check --diff`; delete after trust established.
  5. **Notifications** — configure Semaphore alert integration on failed tasks.
  6. **Consequence** — `main` is live; CI lint gate is load-bearing; merges apply within the week.

- [ ] **Step 4: Update docs + memory pointer** — README: short "Scheduled applies (Semaphore)" section linking `docs/semaphore.md`. CLAUDE.md: same one-liner + note ops playbooks never get scheduled. Update the Claude memory file `semaphore-setup.md` (in the project memory directory) status line to note docs/semaphore.md now exists and is canonical.

- [ ] **Step 5: Lint, syntax, commit, PR 4**

```bash
cd ansible && pipx run ansible-lint && for pb in playbooks/*.yml playbooks/ops/*.yml; do ansible-playbook --syntax-check "$pb" || exit 1; done
git add -A && git commit -m "feat: semaphore runbook + runner key distribution via lab_user"
git push -u origin feat/semaphore-docs
gh pr create --title "feat: Semaphore scheduled-apply wiring + runbook" --body "PR 4 of 4 (spec: docs/superpowers/specs/2026-07-04-ansible-refactor-design.md). Manifests land separately in colinbruner/homelab-k8s per docs/semaphore.md.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

**CHECKPOINT (user):** apply site.yml once manually to distribute the semaphore key; then deploy Semaphore from homelab-k8s (separate session reads `docs/semaphore.md`), configure templates/schedules, run `site.yml` from Semaphore UI once, confirm green before enabling the schedule.

---

## Verification Summary (run at every commit)

```bash
cd ansible && pipx run ansible-lint            # Passed: 0 failure(s), 0 warning(s)
for pb in playbooks/*.yml playbooks/ops/*.yml; do ansible-playbook --syntax-check "$pb" || exit 1; done
```

Live-host verification (`--check --diff`, apply, second-apply-zero-changes) happens only at the user checkpoints between phases.
