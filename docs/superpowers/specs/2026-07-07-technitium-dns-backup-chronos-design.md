# Technitium DNS Backup: Chronos Notifications, Per-Host Layout, Templates

Date: 2026-07-07

## Problem

`roles/technitium/tasks/backup.yml` currently:
- lays down a bash script and two systemd unit files as inline `copy: content:` blocks
- writes both ns1 and ns2 backups into the same shared NFS destination (`dns/`), risking collision/overwrite between the two nameservers
- uses `rsync -a`, which tries to preserve owner/group and fails under the NFS export's `root_squash` (client root is mapped to an unprivileged remote user that can't chown)
- has no external monitoring — a silently failing nightly backup goes unnoticed

## Goals

1. Integrate with Chronos (`https://chronos.bruner.family`) job notifications so backup start/success/failure is externally monitored.
2. Give each nameserver (ns1, ns2) its own backup subdirectory on the shared NFS export.
3. Stop rsync from attempting ownership changes that fail under `root_squash`.
4. Move the backup script and systemd units out of inline `copy: content:` into template files rendered with `ansible.builtin.template`.
5. Add reasonable hardening: prevent overlapping runs, verify backup integrity, report run duration.

## Non-goals

- Building/registering the Chronos jobs or 1Password items themselves (assumed to exist or be created out-of-band).
- Changing backup retention policy, NFS server, or mount options.
- Restore tooling.

## Design

### Chronos integration

Uses Chronos "Path A" (simple ping, no auth) since the jobs are pre-existing per-host jobs, not dynamically created:

```
GET https://chronos.bruner.family/ping/<TOKEN>/start
GET https://chronos.bruner.family/ping/<TOKEN>            (success)
GET https://chronos.bruner.family/ping/<TOKEN>/fail
```

Query params: `rid` (run id, `$(date +%s)-$$`) to correlate lifecycle events, and optional `msg` for error detail or a success summary. All calls use `curl -fsS -G --data-urlencode ... || true` so a Chronos outage never blocks or fails the backup job itself.

Token is per-host (one Chronos job per nameserver), supplied via 1Password:

```yaml
# host_vars/ns1.yml
technitium_backup_chronos_token: "{{ lookup('community.general.onepassword', 'chronos-ns1-dns-backup', field='token', vault='lab') }}"

# host_vars/ns2.yml
technitium_backup_chronos_token: "{{ lookup('community.general.onepassword', 'chronos-ns2-dns-backup', field='token', vault='lab') }}"
```

New role defaults (`roles/technitium/defaults/main.yml`):

```yaml
technitium_backup_chronos_base_url: "https://chronos.bruner.family/ping"
technitium_backup_chronos_token: ""   # must be supplied per-host via 1Password
```

`tasks/backup.yml` asserts the token is non-empty before proceeding, so a host missing its 1Password entry fails the play loudly instead of pinging a broken URL forever.

### Per-host directory layout

NFS export is shared between ns1 and ns2. Destination becomes `{{ technitium_backup_mount_point }}/dns/{{ inventory_hostname }}/` (i.e. `dns/ns1/`, `dns/ns2/`), derived automatically from the Ansible inventory hostname — no new variable needed. `nfs_mount_subdirs` in the `nfs_mount` role invocation creates this nested path directly (the `file` module creates intermediate directories):

```yaml
nfs_mount_subdirs:
  - path: "dns/{{ inventory_hostname }}"
    mode: "0750"
```

### rsync no-chown fix

Replace `rsync -a --delete` with `rsync -rlptD --delete` — equivalent to `-a` minus `-o` (owner) and `-g` (group), which are what trigger the failing chown/chgrp syscalls under `root_squash`. Permissions (`-p`), timestamps (`-t`), symlinks (`-l`), and recursion (`-r`)/device+special files (`-D`) are preserved; ownership is not (it's meaningless on the shared NFS destination anyway).

### Script/unit files as templates

Move from `ansible.builtin.copy: content: |` (inline, Jinja-rendered as task args) to real template files rendered via `ansible.builtin.template`:

- `roles/technitium/templates/dns-backup.sh.j2`
- `roles/technitium/templates/dns-backup.service.j2`
- `roles/technitium/templates/dns-backup.timer.j2`

This matches the existing convention in this role (`templates/technitium-deploy.sh.j2`, `templates/cloudflare.ini.j2`) and keeps `tasks/backup.yml` short.

### Additional hardening

- **flock**: the script acquires a non-blocking lock on `/var/lock/dns-backup.lock` at startup. If already held (an overlapping/hung prior run), it logs and exits 1 without pinging Chronos — this isn't a real job attempt, just a guard against double-execution.
- **Checksum manifest**: after building the tarball, write `sha256sum` output to `dns-backup-<date>.tar.gz.sha256` alongside it, so integrity can be checked later without re-downloading from NFS. Pruned on the same retention `find -mtime` pass as the tarballs.
- **Duration reporting**: elapsed seconds (wall clock from script start to completion) are included in the success ping's `msg=` parameter, since Path A has no dedicated duration field.
- **Failure reporting**: `trap ... ERR` calls the `/fail` Chronos endpoint with the failing exit code in `msg=` before the script exits (via `set -e`).
- `curl` is added to the installed package list (`rsync`, `curl`) since it isn't guaranteed present on a minimal Debian install.

### `tasks/backup.yml` (final shape)

```yaml
- name: Install backup prerequisites
  ansible.builtin.apt:
    pkg: [rsync, curl]
    state: present

- name: Ensure chronos backup token is configured
  ansible.builtin.assert:
    that: technitium_backup_chronos_token | length > 0
    fail_msg: "technitium_backup_chronos_token must be set (see host_vars/ns1.yml / ns2.yml)"

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

### Script sketch (`templates/dns-backup.sh.j2`)

```bash
#!/usr/bin/env bash
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
flock -n 9 || { echo "[$(date)] backup already running, exiting"; exit 1; }

notify() {
  local suffix="$1" msg="${2:-}"
  curl -fsS -G --max-time 10 --data-urlencode "rid=${RUN_ID}" \
    ${msg:+--data-urlencode "msg=${msg}"} \
    "${CHRONOS_BASE}${suffix}" >/dev/null 2>&1 || true
}
trap 'notify "/fail" "backup failed (exit $?)"' ERR

notify "/start"
echo "[$(date)] Starting DNS backup for {{ inventory_hostname }}..."

rsync -rlptD --delete "${SOURCE}" "${DEST}/latest/"
tar -czf "${ARCHIVE}" -C "${DEST}" latest/
sha256sum "${ARCHIVE}" | sed "s|${DEST}/||" > "${ARCHIVE}.sha256"

find "${DEST}" -maxdepth 1 -name "dns-backup-*.tar.gz*" -mtime +{{ technitium_backup_retain_days }} -delete

DURATION=$(( $(date +%s) - START_TIME ))
notify "" "backup complete in ${DURATION}s: $(basename "${ARCHIVE}")"
echo "[$(date)] Backup complete: ${ARCHIVE} (${DURATION}s)"
```

`dns-backup.service.j2` and `dns-backup.timer.j2` carry over the existing unit content unchanged, just as separate template files instead of inline `copy: content:`.

## Testing

- `ansible-playbook playbooks/dns-lb.yml --check --diff` against ns1/ns2 to confirm the task changes render as expected (directory rename, template diffs).
- Manual run: `systemctl start dns-backup.service` on a test host, confirm `dns/<hostname>/latest/` and a fresh tarball+checksum appear on the NFS share, and that the corresponding Chronos job shows a successful ping.
- Force a failure (e.g. temporarily point `SOURCE` at a nonexistent path) to confirm the `/fail` ping fires and the script exits non-zero.
- Confirm rsync no longer emits `chown` permission errors in journal output (`journalctl -u dns-backup.service`).

## Open items / assumptions

- Assumes the 1Password items `chronos-ns1-dns-backup` and `chronos-ns2-dns-backup` (field `token`) either already exist in the `lab` vault or will be created before this role runs — Ansible will fail the lookup otherwise, which is the desired fail-closed behavior.
- Assumes Chronos jobs for `chronos-ns1-dns-backup`/`ns2` are already registered on the Chronos side (Path A doesn't create jobs dynamically).
