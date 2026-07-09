# site.yml Chronos Status Reporting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Report `site.yml`'s run status (start/success/fail) to Chronos via a custom Ansible callback plugin, scoped only to `site.yml`.

**Architecture:** A single callback plugin file (`ansible/callback_plugins/chronos_site_status.py`) hooks `v2_playbook_on_start` (fires once, at the very start of the whole `ansible-playbook` process, before any plays run) and `v2_playbook_on_stats` (fires once, at the very end, after all plays including all three `import_playbook`s regardless of which host group failed). It self-scopes to `site.yml` by checking `playbook._file_name`, and no-ops if `CHRONOS_BASE_URL`/`CHRONOS_SITE_TOKEN` env vars aren't set. `ansible.cfg` is updated to load and enable the plugin; `docs/semaphore.md` documents the new env vars for the Semaphore "site" template.

**Tech Stack:** Python 3 stdlib only (`urllib.request`, `urllib.parse`) — no new pip/collection dependency. Tests use stdlib `unittest`/`unittest.mock`, run with the Python interpreter bundled with the local Ansible install (so `ansible.plugins.callback.CallbackBase` is importable).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-08-site-yml-chronos-status-design.md`
- HTTP calls must use `urllib.request` (stdlib only, no new collection dependency).
- Any HTTP failure (timeout, DNS, connection refused, non-2xx) must be swallowed silently — never raise, never affect the playbook's own exit code or output. This mirrors the existing `|| true` philosophy in `ansible/roles/technitium/templates/dns-backup.sh.j2`.
- Plugin must be inert (zero HTTP calls) for any playbook other than `site.yml`, and inert when `CHRONOS_BASE_URL` or `CHRONOS_SITE_TOKEN` is unset.
- `msg=` query param must be truncated to 300 chars before being sent.
- Ping URL shape (matches the existing per-host Chronos convention in `dns-backup.sh.j2`): `{CHRONOS_BASE_URL}/{CHRONOS_SITE_TOKEN}{suffix}?rid=<run_id>[&msg=<msg>]`, where `suffix` is `/start`, `""` (success), or `/fail`.
- Test file lives outside `ansible/callback_plugins/` (Ansible's plugin loader scans that directory; a stray test file doesn't belong there) — use `tests/callback_plugins/test_chronos_site_status.py` at the repo root, loading the module via `importlib.util.spec_from_file_location` (it's not an installed package).
- Find the Ansible-bundled Python interpreter for running tests via: `head -1 "$(command -v ansible-playbook)" | sed 's/^#!//'` — this works regardless of how Ansible was installed (brew, pipx, apt, venv) since the shebang always points at the interpreter with the `ansible` package importable.

---

### Task 1: Callback plugin — scope detection and start ping

**Files:**
- Create: `ansible/callback_plugins/chronos_site_status.py`
- Create: `tests/callback_plugins/test_chronos_site_status.py`

**Interfaces:**
- Produces: `CallbackModule` class in `ansible/callback_plugins/chronos_site_status.py`, with:
  - `__init__(self)` — sets `self._active = False`, `self._base = ""`, `self._token = ""`, `self._run_id = ""`, `self._start_time = 0.0`
  - `v2_playbook_on_start(self, playbook)` — sets `self._active`, `self._base`, `self._token`, `self._start_time`, `self._run_id`; calls `self._ping("/start")` when active
  - `_ping(self, suffix, msg=None)` — stub in this task (implemented fully in Task 2), must exist so `v2_playbook_on_start` can call it
  - Module-level constant `MAX_MSG_LEN = 300`
- These are consumed directly by Task 2 (implements `_ping`) and Task 3 (implements `v2_playbook_on_stats`), which both live in the same file and edit it further.

- [ ] **Step 1: Write the failing tests for scope detection**

Create `tests/callback_plugins/test_chronos_site_status.py`:

```python
import importlib.util
import os
import unittest
from unittest import mock

MODULE_PATH = os.path.join(
    os.path.dirname(__file__), "..", "..", "ansible", "callback_plugins", "chronos_site_status.py"
)

_spec = importlib.util.spec_from_file_location("chronos_site_status", MODULE_PATH)
chronos_site_status = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(chronos_site_status)


class FakePlaybook:
    def __init__(self, file_name):
        self._file_name = file_name


class ChronosSiteStatusScopeTests(unittest.TestCase):
    def setUp(self):
        patcher = mock.patch.dict(
            os.environ,
            {"CHRONOS_BASE_URL": "http://example.test/ping", "CHRONOS_SITE_TOKEN": "tok123"},
        )
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_activates_for_site_yml_with_env_set(self):
        cb = chronos_site_status.CallbackModule()
        with mock.patch.object(cb, "_ping") as ping:
            cb.v2_playbook_on_start(FakePlaybook("/abs/path/ansible/playbooks/site.yml"))
        self.assertTrue(cb._active)
        ping.assert_called_once_with("/start")

    def test_inactive_for_other_playbook(self):
        cb = chronos_site_status.CallbackModule()
        with mock.patch.object(cb, "_ping") as ping:
            cb.v2_playbook_on_start(FakePlaybook("/abs/path/ansible/playbooks/dns-lb.yml"))
        self.assertFalse(cb._active)
        ping.assert_not_called()

    def test_inactive_when_env_missing(self):
        os.environ.pop("CHRONOS_SITE_TOKEN", None)
        cb = chronos_site_status.CallbackModule()
        with mock.patch.object(cb, "_ping") as ping:
            cb.v2_playbook_on_start(FakePlaybook("site.yml"))
        self.assertFalse(cb._active)
        ping.assert_not_called()


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
ANSIBLE_PY=$(head -1 "$(command -v ansible-playbook)" | sed 's/^#!//')
"$ANSIBLE_PY" -m unittest tests.callback_plugins.test_chronos_site_status -v
```

Expected: FAIL — `ansible/callback_plugins/chronos_site_status.py` doesn't exist yet (`FileNotFoundError` from `spec_from_file_location`/`exec_module`).

- [ ] **Step 3: Write the plugin's scope-detection logic**

Create `ansible/callback_plugins/chronos_site_status.py`:

```python
from __future__ import annotations

import os
import time
import urllib.parse
import urllib.request

from ansible.plugins.callback import CallbackBase

DOCUMENTATION = r"""
name: chronos_site_status
type: notification
short_description: Pings Chronos with site.yml run status
description:
  - Reports start/success/fail of the site.yml converge run to a Chronos
    dead-man's-switch endpoint (https://chronos.bruner.family). Inactive for
    every other playbook and when CHRONOS_BASE_URL / CHRONOS_SITE_TOKEN are
    unset.
"""

MAX_MSG_LEN = 300


class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "notification"
    CALLBACK_NAME = "chronos_site_status"
    CALLBACK_NEEDS_ENABLEMENT = True

    def __init__(self):
        super().__init__()
        self._active = False
        self._base = ""
        self._token = ""
        self._run_id = ""
        self._start_time = 0.0

    def v2_playbook_on_start(self, playbook):
        basename = os.path.basename(getattr(playbook, "_file_name", "") or "")
        base = os.environ.get("CHRONOS_BASE_URL", "")
        token = os.environ.get("CHRONOS_SITE_TOKEN", "")
        if basename != "site.yml" or not base or not token:
            return

        self._active = True
        self._base = base.rstrip("/")
        self._token = token
        self._start_time = time.time()
        self._run_id = f"{int(self._start_time)}-{os.getpid()}"
        self._ping("/start")

    def _ping(self, suffix, msg=None):
        pass
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
ANSIBLE_PY=$(head -1 "$(command -v ansible-playbook)" | sed 's/^#!//')
"$ANSIBLE_PY" -m unittest tests.callback_plugins.test_chronos_site_status -v
```

Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add ansible/callback_plugins/chronos_site_status.py tests/callback_plugins/test_chronos_site_status.py
git commit -m "feat: add chronos_site_status callback plugin with scope detection"
```

---

### Task 2: `_ping` HTTP helper

**Files:**
- Modify: `ansible/callback_plugins/chronos_site_status.py`
- Modify: `tests/callback_plugins/test_chronos_site_status.py`

**Interfaces:**
- Consumes: `CallbackModule`, `MAX_MSG_LEN` from Task 1 (same file/module).
- Produces: full `_ping(self, suffix, msg=None)` implementation — builds `{self._base}/{self._token}{suffix}?rid=<run_id>[&msg=<truncated msg>]` and calls `urllib.request.urlopen(url, timeout=10)`, swallowing all exceptions. Task 3's `v2_playbook_on_stats` calls this with `suffix=""` or `suffix="/fail"`.

- [ ] **Step 1: Write the failing tests for `_ping`**

Add to `tests/callback_plugins/test_chronos_site_status.py` (below the existing imports, add `import urllib.parse` near the top; add this new test class before the `if __name__ == "__main__":` line):

```python
class ChronosSiteStatusPingTests(unittest.TestCase):
    def _make_cb(self):
        cb = chronos_site_status.CallbackModule()
        cb._base = "http://example.test/ping"
        cb._token = "tok123"
        cb._run_id = "111-222"
        return cb

    def test_ping_builds_start_url_with_rid(self):
        cb = self._make_cb()
        with mock.patch.object(chronos_site_status.urllib.request, "urlopen") as urlopen:
            cb._ping("/start")
        called_url = urlopen.call_args[0][0]
        self.assertTrue(called_url.startswith("http://example.test/ping/tok123/start?"))
        self.assertIn("rid=111-222", called_url)
        self.assertNotIn("msg=", called_url)

    def test_ping_includes_msg_when_given(self):
        cb = self._make_cb()
        with mock.patch.object(chronos_site_status.urllib.request, "urlopen") as urlopen:
            cb._ping("", "5s, 2 host(s) ok")
        called_url = urlopen.call_args[0][0]
        self.assertIn("msg=", called_url)

    def test_ping_truncates_long_message(self):
        cb = self._make_cb()
        long_msg = "x" * 500
        with mock.patch.object(chronos_site_status.urllib.request, "urlopen") as urlopen:
            cb._ping("", long_msg)
        called_url = urlopen.call_args[0][0]
        query = called_url.split("?", 1)[1]
        params = urllib.parse.parse_qs(query)
        self.assertEqual(len(params["msg"][0]), chronos_site_status.MAX_MSG_LEN)

    def test_ping_swallows_errors(self):
        cb = self._make_cb()
        with mock.patch.object(
            chronos_site_status.urllib.request, "urlopen", side_effect=OSError("boom")
        ):
            cb._ping("/fail", "some error")  # must not raise
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
ANSIBLE_PY=$(head -1 "$(command -v ansible-playbook)" | sed 's/^#!//')
"$ANSIBLE_PY" -m unittest tests.callback_plugins.test_chronos_site_status -v
```

Expected: FAIL — the 4 new `ChronosSiteStatusPingTests` fail because `_ping` is currently `pass` (no `urlopen` call is made, so `urlopen.call_args` is `None` and `call_args[0]` raises `TypeError`).

- [ ] **Step 3: Implement `_ping`**

Replace the `_ping` stub in `ansible/callback_plugins/chronos_site_status.py`:

```python
    def _ping(self, suffix, msg=None):
        params = {"rid": self._run_id}
        if msg:
            params["msg"] = msg[:MAX_MSG_LEN]
        url = f"{self._base}/{self._token}{suffix}?{urllib.parse.urlencode(params)}"
        try:
            urllib.request.urlopen(url, timeout=10)
        except Exception:
            pass
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
ANSIBLE_PY=$(head -1 "$(command -v ansible-playbook)" | sed 's/^#!//')
"$ANSIBLE_PY" -m unittest tests.callback_plugins.test_chronos_site_status -v
```

Expected: PASS (7 tests total).

- [ ] **Step 5: Commit**

```bash
git add ansible/callback_plugins/chronos_site_status.py tests/callback_plugins/test_chronos_site_status.py
git commit -m "feat: implement chronos_site_status ping HTTP helper"
```

---

### Task 3: `v2_playbook_on_stats` — success/failure detection

**Files:**
- Modify: `ansible/callback_plugins/chronos_site_status.py`
- Modify: `tests/callback_plugins/test_chronos_site_status.py`

**Interfaces:**
- Consumes: `CallbackModule._ping(self, suffix, msg=None)` and `self._active`/`self._start_time` from Tasks 1–2 (same file/module).
- Produces: `v2_playbook_on_stats(self, stats)` — final method needed to complete the plugin. No later task depends on new interfaces from this one.

- [ ] **Step 1: Write the failing tests for `v2_playbook_on_stats`**

Add to `tests/callback_plugins/test_chronos_site_status.py` (add `import time` near the top; add this class before `if __name__ == "__main__":`):

```python
class FakeStats:
    def __init__(self, processed=None, failures=None, dark=None):
        self.processed = processed or {}
        self.failures = failures or {}
        self.dark = dark or {}


class ChronosSiteStatusStatsTests(unittest.TestCase):
    def test_noop_when_inactive(self):
        cb = chronos_site_status.CallbackModule()
        cb._active = False
        with mock.patch.object(cb, "_ping") as ping:
            cb.v2_playbook_on_stats(FakeStats())
        ping.assert_not_called()

    def test_success_pings_empty_suffix_with_host_count(self):
        cb = chronos_site_status.CallbackModule()
        cb._active = True
        cb._start_time = time.time() - 5
        stats = FakeStats(processed={"h1": 1, "h2": 1})
        with mock.patch.object(cb, "_ping") as ping:
            cb.v2_playbook_on_stats(stats)
        ping.assert_called_once()
        args = ping.call_args[0]
        self.assertEqual(args[0], "")
        self.assertIn("2 host(s) ok", args[1])

    def test_failure_pings_fail_suffix_with_hostnames(self):
        cb = chronos_site_status.CallbackModule()
        cb._active = True
        cb._start_time = time.time() - 5
        stats = FakeStats(
            processed={"h1": 1, "h2": 1, "h3": 1},
            failures={"h1": 1},
            dark={"h3": 1},
        )
        with mock.patch.object(cb, "_ping") as ping:
            cb.v2_playbook_on_stats(stats)
        args = ping.call_args[0]
        self.assertEqual(args[0], "/fail")
        self.assertIn("h1", args[1])
        self.assertIn("h3", args[1])
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
ANSIBLE_PY=$(head -1 "$(command -v ansible-playbook)" | sed 's/^#!//')
"$ANSIBLE_PY" -m unittest tests.callback_plugins.test_chronos_site_status -v
```

Expected: FAIL — `AttributeError: 'CallbackModule' object has no attribute 'v2_playbook_on_stats'` for the 3 new tests.

- [ ] **Step 3: Implement `v2_playbook_on_stats`**

Add to `ansible/callback_plugins/chronos_site_status.py`, after `v2_playbook_on_start`:

```python
    def v2_playbook_on_stats(self, stats):
        if not self._active:
            return

        elapsed = int(time.time() - self._start_time)
        failed = sorted(set(stats.failures) | set(stats.dark))
        if not failed:
            ok_hosts = len(stats.processed)
            self._ping("", f"{elapsed}s, {ok_hosts} host(s) ok")
        else:
            self._ping("/fail", f"{elapsed}s, failed/unreachable: {', '.join(failed)}")
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
ANSIBLE_PY=$(head -1 "$(command -v ansible-playbook)" | sed 's/^#!//')
"$ANSIBLE_PY" -m unittest tests.callback_plugins.test_chronos_site_status -v
```

Expected: PASS (10 tests total).

- [ ] **Step 5: Commit**

```bash
git add ansible/callback_plugins/chronos_site_status.py tests/callback_plugins/test_chronos_site_status.py
git commit -m "feat: report site.yml success/failure to chronos via playbook stats"
```

---

### Task 4: Wire up ansible.cfg, docs, and end-to-end smoke test

**Files:**
- Modify: `ansible/ansible.cfg`
- Modify: `docs/semaphore.md`

**Interfaces:**
- Consumes: the completed `ansible/callback_plugins/chronos_site_status.py` from Tasks 1–3 (no code changes to it in this task).
- Produces: nothing consumed by a later task — this is the final task.

- [ ] **Step 1: Enable the callback plugin in `ansible.cfg`**

Read `ansible/ansible.cfg` first (current contents, for reference):

```ini
[defaults]
inventory = inventory/hosts.yml
roles_path = roles
host_key_checking = False
deprecation_warnings = False

[ssh_connection]
ssh_args = -o ControlMaster=no -o ControlPath=none
```

Edit `[defaults]` to add two lines after `host_key_checking = False`:

```ini
[defaults]
inventory = inventory/hosts.yml
roles_path = roles
host_key_checking = False
callback_plugins = callback_plugins
callbacks_enabled = chronos_site_status
# Suppress deprecation warnings from ansible.posix collection internals (to_native
# import path). Remove once ansible.posix publishes a fix upstream.
deprecation_warnings = False

[ssh_connection]
ssh_args = -o ControlMaster=no -o ControlPath=none
```

- [ ] **Step 2: Verify Ansible loads the plugin without error**

```bash
cd ansible
CHRONOS_BASE_URL=http://127.0.0.1:8123/ping CHRONOS_SITE_TOKEN=smoketest \
  ansible-playbook playbooks/dns-lb.yml --list-tasks 2>&1 | tail -20
```

Expected: task list prints normally, no Python tracebacks, no "couldn't resolve module/action" or callback-loading errors. (`--list-tasks` loads callback plugins but doesn't run plays, so no ping fires here — this step only confirms the plugin file is syntactically valid and importable by Ansible itself, not just by the test's `importlib` loader.)

- [ ] **Step 3: End-to-end smoke test against a local HTTP listener**

In one terminal, start a disposable listener that logs requests:

```bash
python3 -m http.server 8123 --bind 127.0.0.1 &
LISTENER_PID=$!
```

In another command, run `site.yml` with a fake local inventory so no real lab hosts are touched (the `proxmox`/`dns_lb`/`pxe` groups won't match any host under `-i localhost,`, so all three imported plays report "no hosts matched" and skip — this still exercises `v2_playbook_on_start`/`v2_playbook_on_stats` for the real `site.yml` file):

```bash
cd ansible
CHRONOS_BASE_URL=http://127.0.0.1:8123/ping CHRONOS_SITE_TOKEN=smoketest \
  ansible-playbook -i localhost, -c local playbooks/site.yml
```

Expected: the playbook run completes with exit code 0 (plays skip, nothing fails). Check the `http.server` terminal output — it should show two GET requests logged: one to `/ping/smoketest/start?rid=...` and one to `/ping/smoketest?rid=...&msg=...host(s)+ok` (200 responses aren't required for the plugin to be "correct" — `http.server` will 404 both, which is fine, since the ping helper only cares that the request was sent, not the response).

Then stop the listener:

```bash
kill $LISTENER_PID
```

- [ ] **Step 4: Confirm scope check holds for other playbooks**

```bash
cd ansible
python3 -m http.server 8123 --bind 127.0.0.1 > /tmp/http_server.log 2>&1 &
LISTENER_PID=$!
CHRONOS_BASE_URL=http://127.0.0.1:8123/ping CHRONOS_SITE_TOKEN=smoketest \
  ansible-playbook -i localhost, -c local playbooks/dns-lb.yml
kill $LISTENER_PID
cat /tmp/http_server.log
```

Expected: `/tmp/http_server.log` is empty (or contains only the startup line) — no `GET /ping/...` lines, confirming the plugin stays inert for a non-`site.yml` playbook.

- [ ] **Step 5: Document the new env vars in `docs/semaphore.md`**

Read `docs/semaphore.md` first, then edit the "Environment" bullet (item 3 in the "In-Semaphore setup" numbered list). Current text:

```markdown
3. **Environment** — an environment exposing the two 1Password Connect
   variables (`OP_CONNECT_HOST`, `OP_CONNECT_TOKEN`) to task runs, matching the
   values injected into the pod.
```

Replace with:

```markdown
3. **Environment** — an environment exposing the two 1Password Connect
   variables (`OP_CONNECT_HOST`, `OP_CONNECT_TOKEN`) to task runs, matching the
   values injected into the pod. The **`site`** task template additionally
   needs `CHRONOS_BASE_URL` (`https://chronos.bruner.family/ping`) and
   `CHRONOS_SITE_TOKEN` (from a `chronos-site-converge` 1Password item, field
   `token`, vault `lab` — same pattern as the per-host
   `chronos-ns1-dns-backup`/`chronos-ns2-dns-backup` items) so the
   `chronos_site_status` callback plugin (`ansible/callback_plugins/`) can
   report the scheduled converge run's start/success/failure. Other task
   templates don't need these vars — the plugin only activates for
   `site.yml`.
```

- [ ] **Step 6: Commit**

```bash
git add ansible/ansible.cfg docs/semaphore.md
git commit -m "feat: enable chronos_site_status callback and document Semaphore env vars"
```

---

## Post-plan follow-up (not part of this plan)

- Create the `chronos-site-converge` Chronos job and matching 1Password item out-of-band (same assumption the DNS backup Chronos integration made) before enabling this in the real Semaphore "site" template's environment.
