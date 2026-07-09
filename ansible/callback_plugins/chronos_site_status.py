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
USER_AGENT = "chronos-site-status/1.0"


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

    def _ping(self, suffix, msg=None):
        try:
            params = {"rid": self._run_id}
            if msg:
                params["msg"] = msg[:MAX_MSG_LEN]
            url = f"{self._base}/{self._token}{suffix}?{urllib.parse.urlencode(params)}"
            # Cloudflare's bot protection in front of chronos.bruner.family blocks
            # urllib's default "Python-urllib/x.y" User-Agent with a 403 (error 1010).
            request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            urllib.request.urlopen(request, timeout=10)
        except Exception as exc:
            # Never fail the play over a Chronos outage — but leave a visible
            # breadcrumb (token redacted) instead of failing completely silently.
            self._display.warning(f"chronos_site_status: ping to {self._base}/<token>{suffix} failed: {exc}")
