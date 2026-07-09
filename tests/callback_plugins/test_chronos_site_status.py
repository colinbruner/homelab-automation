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
