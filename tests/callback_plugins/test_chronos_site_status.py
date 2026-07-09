import importlib.util
import os
import unittest
import urllib.parse
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


if __name__ == "__main__":
    unittest.main()
