# site.yml Job Status Reporting via Chronos

Date: 2026-07-08

## Problem

`ansible/playbooks/site.yml` is the converge-everything entry point, scheduled
weekly by Semaphore (`docs/semaphore.md`). Semaphore has its own "failed task"
alert integration, but there's no external dead-man's-switch monitoring of the
job itself — if Semaphore's scheduler silently stops firing, or a run hangs
without ever reaching a failure state Semaphore notices, nothing surfaces it.

The DNS backup role (`roles/technitium/tasks/backup.yml`) already integrates
with Chronos (`https://chronos.bruner.family`), a ping-style dead-man's-switch
monitoring service, for exactly this kind of "did the scheduled job run and
succeed" visibility.

## Goal

Report `site.yml` run status (start / success / failure) to Chronos, using
the same Path A ping convention already established for the DNS backup job,
scoped only to `site.yml` (not `dns-lb.yml`, `pxe.yml`, `proxmox.yml`, or any
`ops/` playbook).

## Non-goals

- Per-sub-playbook (proxmox / dns-lb / pxe) granularity in the failure report
  — only whole-run pass/fail.
- Registering the Chronos job or 1Password item itself (assumed created
  out-of-band, same as the DNS backup Chronos jobs).
- Changing Semaphore's own failed-task alerting (`docs/semaphore.md`
  "Notifications" section) — this is additive, independent monitoring.

## Why not a task in site.yml

`site.yml` is three `ansible.builtin.import_playbook` plays, each targeting a
different host group (proxmox, dns_lb, pxe). Ansible does not abort the whole
run when one import fails — it continues to later plays that target different
hosts (only the failed hosts are excluded from later plays that target them
again). A literal "ping success" task added as a final play in site.yml would
still execute after an earlier import failed, sending a false success ping.
`import_playbook` also can't be wrapped in a task-level `block`/`rescue`, so
there's no way to catch a failure from inside site.yml's own play list.

The only point that reliably sees the true end-to-end result of the whole
`ansible-playbook` process — regardless of which host group failed — is the
process lifecycle itself. Ansible exposes this via callback plugins.

## Design

### Callback plugin

New file: `ansible/callback_plugins/chronos_site_status.py`

- `CALLBACK_TYPE = 'notification'`, `CALLBACK_NAME = 'chronos_site_status'`.
- `v2_playbook_on_start(self, playbook)`:
  - Resolve the top-level playbook's basename from `playbook._file_name`.
  - If it is not `site.yml`, set an internal `self._active = False` and
    return — no further hooks in this plugin do anything for that run.
  - If `CHRONOS_BASE_URL` or `CHRONOS_SITE_TOKEN` env vars are unset, also
    set `self._active = False` (safe no-op for local/manual runs without
    Chronos configured).
  - Otherwise record `self._start_time = time.time()`, generate
    `self._run_id = f"{int(self._start_time)}-{os.getpid()}"`, and GET
    `{CHRONOS_BASE_URL}/{CHRONOS_SITE_TOKEN}/start?rid=<run_id>`.
- `v2_playbook_on_stats(self, stats)`:
  - No-op if `self._active` is falsy.
  - Inspect `stats.failures` and `stats.dark` (both `dict[host] -> count`
    keyed by hostname). If both are empty across all hosts in
    `stats.processed`, it's a success: GET the base ping URL (no suffix)
    with `msg=<elapsed>s, <N> host(s) ok`.
  - Otherwise it's a failure: GET `/fail` with
    `msg=<elapsed>s, failed/unreachable: <comma-joined hostnames>`
    (truncate `msg` to a safe length, e.g. 300 chars, before URL-encoding).
  - Both requests include `rid=<run_id>` to correlate with the `/start` ping.
- All HTTP calls go through one internal helper (`_ping(self, suffix, msg)`)
  using `urllib.request.urlopen` (stdlib only, no new collection
  dependency), a 10s timeout, and a bare `try/except Exception: pass` —
  a Chronos outage or network blip must never raise, log a traceback into
  the run, or affect the play's exit code. This mirrors the `|| true`
  philosophy already used in `templates/dns-backup.sh.j2`.

### `ansible.cfg`

Add to `[defaults]`:

```ini
callback_plugins = callback_plugins
callbacks_enabled = chronos_site_status
```

The plugin is always loaded for every `ansible-playbook` invocation in this
project (that's how Ansible callback loading works), but its own internal
`site.yml`-basename check keeps it inert for every other playbook.

### Configuration (env vars)

| Var | Purpose |
|---|---|
| `CHRONOS_BASE_URL` | e.g. `https://chronos.bruner.family/ping` — shared across any future Chronos-integrated jobs. |
| `CHRONOS_SITE_TOKEN` | Path A token for the `site.yml` converge job specifically (distinct from the per-host DNS backup tokens). |

Neither is a new concept: they follow the same "env var supplied by the
Semaphore task template's environment, sourced from 1Password" mechanism
already documented for `OP_CONNECT_HOST`/`OP_CONNECT_TOKEN` in
`docs/semaphore.md`.

### `docs/semaphore.md` update

Add a short note under the "Environment" step (step 3) that the `site` task
template's environment additionally needs `CHRONOS_BASE_URL` and
`CHRONOS_SITE_TOKEN`, sourced from a new `chronos-site-converge` 1Password
item (field `token`, vault `lab`) — same pattern as the existing per-host
`chronos-ns1-dns-backup` / `chronos-ns2-dns-backup` items.

## Testing

- Local run against a throwaway listener (`webhook.site` test URL or
  `nc -l 8080`) with `CHRONOS_BASE_URL`/`CHRONOS_SITE_TOKEN` exported:
  `ansible-playbook playbooks/site.yml --check` and confirm a `/start` hit
  followed by one success hit, both carrying the same `rid`.
- Force a failure (e.g. an unreachable host in one inventory group) and
  confirm the `/fail` ping fires with that host named in `msg=`, and that
  the playbook's own exit code/behavior is unchanged (plugin never raises).
- Run `ansible-playbook playbooks/dns-lb.yml --check` directly and confirm
  zero HTTP calls are made (scope check holds).
- Run with `CHRONOS_BASE_URL`/`CHRONOS_SITE_TOKEN` unset and confirm the
  playbook completes normally with no errors or warnings from the plugin.

## Open items / assumptions

- Assumes the `chronos-site-converge` Chronos job and matching 1Password item
  are created out-of-band before this ships to Semaphore, same fail-open
  assumption as the existing DNS backup Chronos integration.
- `stats.processed` host names are used verbatim in `msg=`; no attempt is
  made to map a failed host back to which of the three imported playbooks
  (proxmox/dns-lb/pxe) it belongs to — matches the stated non-goal.
