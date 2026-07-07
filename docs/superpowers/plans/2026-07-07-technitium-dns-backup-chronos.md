# Technitium DNS Backup: Chronos Notifications + Templates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework `roles/technitium/tasks/backup.yml` so the nightly DNS backup pings Chronos for external monitoring, writes to per-nameserver NFS subdirectories, stops rsync from failing on `root_squash` chown attempts, and is rendered from real template files instead of inline `copy: content:` blocks.

**Architecture:** The backup script and its two systemd units move to `roles/technitium/templates/*.j2`, rendered via `ansible.builtin.template`. `tasks/backup.yml` gains an `assert` guard on the new Chronos token var and switches the `nfs_mount` subdir to a per-host path. Two `host_vars` files gain a 1Password lookup for their host's Chronos token.

**Tech Stack:** Ansible (`ansible.builtin.template`, `ansible.builtin.assert`, `community.general.onepassword` lookup), bash (`flock`, `curl`, `rsync`, `sha256sum`), systemd (`.service`/`.timer` units).

## Global Constraints

- LF line endings only, no CRLF (global CLAUDE.md).
- Secrets are never hardcoded — resolved at runtime via `community.general.onepassword` lookups in `group_vars`/`host_vars`, vault `lab` (project CLAUDE.md).
- Tasks must be idempotent (project CLAUDE.md convention).
- No automated test suite exists in this repo (no CI, no molecule). Validation per task uses `yamllint`, `ansible-playbook --syntax-check`, and — for the bash template — local rendering with dummy vars followed by `bash -n` and `shellcheck`, in place of unit tests.
- `ansible-lint` is configured (`.ansible-lint`, profile `production`) but not installed in this environment; skip it if unavailable, don't install new tooling as part of this plan.
- Do not create the 1Password items or Chronos jobs themselves — the plan wires up the lookups/pings assuming `chronos-ns1-dns-backup` / `chronos-ns2-dns-backup` (field `token`, vault `lab`) exist or will be created out-of-band by the user.

---

### Task 1: Role defaults — Chronos vars

**Files:**
- Modify: `ansible/roles/technitium/defaults/main.yml`

**Interfaces:**
- Produces: `technitium_backup_chronos_base_url` (string, default `"https://chronos.bruner.family/ping"`), `technitium_backup_chronos_token` (string, default `""`) — consumed by Task 4 (assert) and Task 2 (script template).

- [ ] **Step 1: Add the two new defaults**

Append to the end of `ansible/roles/technitium/defaults/main.yml` (after the existing `technitium_backup_schedule` line):

```yaml

# Chronos job monitoring (https://chronos.bruner.family) — Path A ping-style
# notifications. Token is per-host (one Chronos job per nameserver); must be
# supplied via host_vars (1Password lookup), e.g. host_vars/ns1.yml.
technitium_backup_chronos_base_url: "https://chronos.bruner.family/ping"
technitium_backup_chronos_token: ""
```

- [ ] **Step 2: Validate YAML**

Run: `yamllint ansible/roles/technitium/defaults/main.yml`
Expected: no output (clean).

- [ ] **Step 3: Commit**

```bash
cd ansible
git add roles/technitium/defaults/main.yml
git commit -m "feat: add chronos backup notification defaults to technitium role"
```

---

### Task 2: host_vars — Chronos tokens for ns1/ns2

**Files:**
- Modify: `ansible/inventory/host_vars/ns1.yml`
- Modify: `ansible/inventory/host_vars/ns2.yml`

**Interfaces:**
- Consumes: none.
- Produces: `technitium_backup_chronos_token` resolved value on each host, overriding the empty role default from Task 1.

- [ ] **Step 1: Add the lookup to ns1**

`ansible/inventory/host_vars/ns1.yml` currently reads:

```yaml
---
# FQDN for this node's Let's Encrypt certificate.
# Must match the hostname Technitium will use after cluster initialization
# (i.e. <hostname>.<cluster-domain> from the cluster init dialog).
technitium_cert_domain: "ns1.colinbruner.com"
```

Append:

```yaml

# Chronos ping token for the nightly DNS backup job (this host's job only).
technitium_backup_chronos_token: "{{ lookup('community.general.onepassword', 'chronos-ns1-dns-backup', field='token', vault='lab') }}"
```

- [ ] **Step 2: Add the lookup to ns2**

`ansible/inventory/host_vars/ns2.yml` currently reads:

```yaml
---
# FQDN for this node's Let's Encrypt certificate.
# Must match the hostname Technitium will use after cluster initialization
# (i.e. <hostname>.<cluster-domain> from the cluster init dialog).
technitium_cert_domain: "ns2.colinbruner.com"
```

Append:

```yaml

# Chronos ping token for the nightly DNS backup job (this host's job only).
technitium_backup_chronos_token: "{{ lookup('community.general.onepassword', 'chronos-ns2-dns-backup', field='token', vault='lab') }}"
```

- [ ] **Step 3: Validate YAML**

Run: `yamllint ansible/inventory/host_vars/ns1.yml ansible/inventory/host_vars/ns2.yml`
Expected: no output (clean).

- [ ] **Step 4: Commit**

```bash
cd ansible
git add inventory/host_vars/ns1.yml inventory/host_vars/ns2.yml
git commit -m "feat: wire per-host chronos backup tokens via 1Password"
```

---

### Task 3: Backup script template

**Files:**
- Create: `ansible/roles/technitium/templates/dns-backup.sh.j2`

**Interfaces:**
- Consumes: `technitium_data_dir`, `technitium_backup_mount_point`, `technitium_backup_chronos_base_url`, `technitium_backup_chronos_token`, `technitium_backup_retain_days`, `inventory_hostname` (all already-existing or Task 1 vars).
- Produces: rendered script installed at `/usr/local/bin/dns-backup.sh` by Task 5.

- [ ] **Step 1: Write the template**

Create `ansible/roles/technitium/templates/dns-backup.sh.j2`:

```bash
#!/usr/bin/env bash
# Technitium DNS nightly backup script.
# Managed by Ansible — do not edit manually.
set -euo pipefail

SOURCE="{{ technitium_data_dir }}/"
DEST="{{ technitium_backup_mount_point }}/dns/{{ inventory_hostname }}"
DATE=$(date +%Y%m%d-%H%M%S)
ARCHIVE="${DEST}/dns-backup-${DATE}.tar.gz"
LOCK_FILE="/var/lock/dns-backup.lock"
CHRONOS_BASE="{{ technitium_backup_chronos_base_url }}/{{ technitium_backup_chronos_token }}"
RUN_ID="$(date +%s)-$$"
START_TIME=$(date +%s)

exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
  echo "[$(date)] Another backup run is already in progress; exiting."
  exit 1
fi

notify() {
  local suffix="$1" msg="${2:-}"
  local args=(-fsS -G --max-time 10 --data-urlencode "rid=${RUN_ID}")
  if [[ -n "${msg}" ]]; then
    args+=(--data-urlencode "msg=${msg}")
  fi
  curl "${args[@]}" "${CHRONOS_BASE}${suffix}" >/dev/null 2>&1 || true
}
trap 'notify "/fail" "backup failed (exit $?)"' ERR

notify "/start"
echo "[$(date)] Starting DNS backup for {{ inventory_hostname }}..."

# Sync to a staging directory then archive. -rlptD (not -a) so we never try
# to preserve owner/group: the NFS export uses root_squash, and chown/chgrp
# from the squashed client fails.
rsync -rlptD --delete "${SOURCE}" "${DEST}/latest/"
tar -czf "${ARCHIVE}" -C "${DEST}" latest/
sha256sum "${ARCHIVE}" | sed "s|${DEST}/||" > "${ARCHIVE}.sha256"

# Remove backups (and their checksums) older than {{ technitium_backup_retain_days }} days
find "${DEST}" -maxdepth 1 -name "dns-backup-*.tar.gz*" -mtime +{{ technitium_backup_retain_days }} -delete

DURATION=$(( $(date +%s) - START_TIME ))
notify "" "backup complete in ${DURATION}s: $(basename "${ARCHIVE}")"
echo "[$(date)] Backup complete: ${ARCHIVE} (${DURATION}s)"
```

- [ ] **Step 2: Render locally with dummy vars and check bash syntax**

From the `ansible/` directory, render the template through Ansible's own Jinja engine using a throwaway local play so the check exercises the real templating rules (no live hosts, no secrets):

```bash
cd ansible
cat > /tmp/render-check.yml <<'EOF'
---
- hosts: localhost
  gather_facts: false
  vars:
    technitium_data_dir: /etc/dns
    technitium_backup_mount_point: /mnt/backup/homelab
    technitium_backup_chronos_base_url: "https://chronos.bruner.family/ping"
    technitium_backup_chronos_token: "dummy-token"
    technitium_backup_retain_days: 7
    inventory_hostname: ns1
  tasks:
    - name: Render dns-backup.sh
      ansible.builtin.template:
        src: roles/technitium/templates/dns-backup.sh.j2
        dest: /tmp/dns-backup.sh.rendered
        mode: "0750"
EOF
ansible-playbook /tmp/render-check.yml
bash -n /tmp/dns-backup.sh.rendered
shellcheck /tmp/dns-backup.sh.rendered
rm /tmp/render-check.yml /tmp/dns-backup.sh.rendered
```

Expected: `ansible-playbook` reports `changed=1`, `bash -n` prints nothing (valid syntax), `shellcheck` reports no errors (warnings about `SC2064`-style trap quoting are expected and fine — the single-quoted trap is intentional so `$?` is evaluated at trap-fire time, not at `trap` registration time).

- [ ] **Step 3: Commit**

```bash
cd ansible
git add roles/technitium/templates/dns-backup.sh.j2
git commit -m "feat: add templated DNS backup script with chronos notifications"
```

---

### Task 4: Systemd unit templates

**Files:**
- Create: `ansible/roles/technitium/templates/dns-backup.service.j2`
- Create: `ansible/roles/technitium/templates/dns-backup.timer.j2`

**Interfaces:**
- Consumes: `technitium_backup_schedule` (existing var).
- Produces: rendered units installed at `/etc/systemd/system/dns-backup.{service,timer}` by Task 5.

- [ ] **Step 1: Write the service unit template**

Create `ansible/roles/technitium/templates/dns-backup.service.j2`:

```ini
[Unit]
Description=Technitium DNS nightly backup
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/dns-backup.sh
StandardOutput=journal
StandardError=journal
```

- [ ] **Step 2: Write the timer unit template**

Create `ansible/roles/technitium/templates/dns-backup.timer.j2`:

```ini
[Unit]
Description=Run Technitium DNS backup nightly

[Timer]
OnCalendar=*-*-* {{ technitium_backup_schedule }}
Persistent=true

[Install]
WantedBy=timers.target
```

- [ ] **Step 3: Render locally and sanity-check contents**

```bash
cd ansible
cat > /tmp/render-check.yml <<'EOF'
---
- hosts: localhost
  gather_facts: false
  vars:
    technitium_backup_schedule: "02:00:00"
  tasks:
    - name: Render service unit
      ansible.builtin.template:
        src: roles/technitium/templates/dns-backup.service.j2
        dest: /tmp/dns-backup.service.rendered
    - name: Render timer unit
      ansible.builtin.template:
        src: roles/technitium/templates/dns-backup.timer.j2
        dest: /tmp/dns-backup.timer.rendered
EOF
ansible-playbook /tmp/render-check.yml
grep -q "ExecStart=/usr/local/bin/dns-backup.sh" /tmp/dns-backup.service.rendered && echo "service OK"
grep -q "OnCalendar=\*-\*-\* 02:00:00" /tmp/dns-backup.timer.rendered && echo "timer OK"
rm /tmp/render-check.yml /tmp/dns-backup.service.rendered /tmp/dns-backup.timer.rendered
```

Expected: `ansible-playbook` reports `changed=2`, both `grep` checks print their `OK` line (`systemd-analyze verify` isn't available on this macOS dev machine, so structural grep checks stand in for it — the content is unchanged from the previously-working inline units, only relocated).

- [ ] **Step 4: Commit**

```bash
cd ansible
git add roles/technitium/templates/dns-backup.service.j2 roles/technitium/templates/dns-backup.timer.j2
git commit -m "feat: move DNS backup systemd units to templates"
```

---

### Task 5: Rewrite `tasks/backup.yml`

**Files:**
- Modify: `ansible/roles/technitium/tasks/backup.yml`

**Interfaces:**
- Consumes: `technitium_backup_chronos_token` (Task 1/2), `dns-backup.sh.j2` / `dns-backup.service.j2` / `dns-backup.timer.j2` (Tasks 3/4), existing `nfs_mount` role interface (`nfs_mount_server`, `nfs_mount_export`, `nfs_mount_point`, `nfs_mount_opts`, `nfs_mount_mode`, `nfs_mount_subdirs`).
- Produces: `/usr/local/bin/dns-backup.sh`, `/etc/systemd/system/dns-backup.{service,timer}`, `{{ technitium_backup_mount_point }}/dns/{{ inventory_hostname }}/` on the NFS share.

- [ ] **Step 1: Replace the file contents**

Replace the entire contents of `ansible/roles/technitium/tasks/backup.yml` with:

```yaml
---
- name: Install backup prerequisites
  ansible.builtin.apt:
    pkg:
      - rsync
      - curl
    state: present

- name: Ensure chronos backup token is configured
  ansible.builtin.assert:
    that:
      - technitium_backup_chronos_token | length > 0
    fail_msg: >-
      technitium_backup_chronos_token must be set (see host_vars/ns1.yml /
      host_vars/ns2.yml) for Chronos backup notifications.

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
      - path: "dns/{{ inventory_hostname }}"
        mode: "0750"

- name: Install backup script
  ansible.builtin.template:
    src: dns-backup.sh.j2
    dest: /usr/local/bin/dns-backup.sh
    mode: "0750"

- name: Install backup systemd service unit
  ansible.builtin.template:
    src: dns-backup.service.j2
    dest: /etc/systemd/system/dns-backup.service
    mode: "0644"
  notify: Reload systemd

- name: Install backup systemd timer unit
  ansible.builtin.template:
    src: dns-backup.timer.j2
    dest: /etc/systemd/system/dns-backup.timer
    mode: "0644"
  notify: Reload systemd

- name: Flush handlers
  ansible.builtin.meta: flush_handlers

- name: Enable and start backup timer
  ansible.builtin.service:
    name: dns-backup.timer
    enabled: true
    state: started
```

- [ ] **Step 2: Validate YAML and playbook syntax**

```bash
cd ansible
yamllint roles/technitium/tasks/backup.yml
ansible-playbook playbooks/dns-lb.yml --syntax-check
```

Expected: `yamllint` prints nothing; `ansible-playbook --syntax-check` prints `playbook: playbooks/dns-lb.yml`.

- [ ] **Step 3: Commit**

```bash
cd ansible
git add roles/technitium/tasks/backup.yml
git commit -m "refactor: template-ize DNS backup, add per-host dirs and chronos guard"
```

---

### Task 6: Full-repo validation sweep

**Files:**
- None (validation only).

**Interfaces:**
- Consumes: everything from Tasks 1-5.
- Produces: confidence the whole changeset lints and parses clean together.

- [ ] **Step 1: Lint every changed file together**

```bash
cd ansible
yamllint \
  roles/technitium/defaults/main.yml \
  roles/technitium/tasks/backup.yml \
  inventory/host_vars/ns1.yml \
  inventory/host_vars/ns2.yml
```

Expected: no output.

- [ ] **Step 2: Syntax-check every playbook that pulls in the technitium role**

```bash
cd ansible
ansible-playbook playbooks/dns-lb.yml --syntax-check
ansible-playbook playbooks/site.yml --syntax-check
```

Expected: both print their `playbook: <path>` line with no errors.

- [ ] **Step 3: Confirm connectivity for a future real run (manual, informational)**

```bash
cd ansible
ansible dns_lb -m ping -o
```

Expected: `ns1 | SUCCESS` and `ns2 | SUCCESS`. This confirms hosts are reachable; it does NOT confirm the Chronos 1Password items exist. Before actually applying (`ansible-playbook playbooks/dns-lb.yml`), the user must:
1. Create 1Password items `chronos-ns1-dns-backup` and `chronos-ns2-dns-backup` (field `token`) in the `lab` vault.
2. Export `OP_CONNECT_HOST` and `OP_CONNECT_TOKEN` per the project README/CLAUDE.md.

Do not attempt a real (non-syntax-check) run against `ns1`/`ns2` as part of this plan — that's a live infra change the user should trigger themselves once the 1Password items exist.

- [ ] **Step 4: Final commit (if any stray changes)**

```bash
cd ansible
git status
```

Expected: clean (everything already committed in Tasks 1-5). If not, `git add` and commit the remainder with a message describing what was left over.
