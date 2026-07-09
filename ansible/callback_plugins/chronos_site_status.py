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
