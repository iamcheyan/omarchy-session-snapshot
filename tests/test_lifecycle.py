import importlib.util
from importlib.machinery import SourceFileLoader
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ENGINE = Path(__file__).resolve().parents[1] / "bin" / "omarchy-session-snapshot"
ROOT = ENGINE.parents[1]
SPEC = importlib.util.spec_from_loader(
    "session_snapshot", SourceFileLoader("session_snapshot", str(ENGINE))
)
snapshot = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(snapshot)


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        state = Path(self.tempdir.name) / "session"
        self.paths = mock.patch.multiple(
            snapshot,
            STATE_DIR=state,
            LAST_FILE=state / "last.json",
            LAST_BAK_FILE=state / "last.json.bak",
            RESTORE_RESULT_FILE=state / "restore-result.json",
            AUTO_RESTORE_FILE=state / "restore-on-next-start",
            SAVE_REQUESTED_FILE=state / "save-requested",
            RESTORE_LOCK=state / "restore.lock",
            KITTY_SESSION_DIR=state / "kitty",
        )
        self.paths.start()
        state.mkdir(parents=True)

    def tearDown(self):
        self.paths.stop()
        self.tempdir.cleanup()

    def write_snapshot(self, clients=1):
        snapshot.LAST_FILE.write_text(json.dumps({
            "version": 1,
            "savedAt": 123,
            "clients": [{"class": f"app-{index}"} for index in range(clients)],
        }))

    def test_requested_shutdown_arms_rolling_snapshot_without_hyprland(self):
        self.write_snapshot(2)
        snapshot.save_requested()
        with mock.patch.object(snapshot, "_compositor_is_reachable", return_value=False), \
                mock.patch.object(snapshot, "save") as save:
            snapshot.save_auto_if_stale()
        self.assertFalse(save.called)
        self.assertFalse(snapshot.SAVE_REQUESTED_FILE.exists())
        marker = json.loads(snapshot.AUTO_RESTORE_FILE.read_text())
        self.assertTrue(marker["armed"])

    def test_requested_shutdown_does_not_arm_empty_snapshot(self):
        self.write_snapshot(0)
        snapshot.save_requested()
        with mock.patch.object(snapshot, "_compositor_is_reachable", return_value=False):
            snapshot.save_auto_if_stale()
        self.assertFalse(snapshot.AUTO_RESTORE_FILE.exists())

    def test_requested_shutdown_arms_existing_snapshot_when_live_capture_is_empty(self):
        self.write_snapshot(3)
        with mock.patch.object(snapshot, "save", return_value=None), \
                mock.patch.object(snapshot, "_hypr_available", return_value=True):
            snapshot.save_auto(requested=True)
        marker = json.loads(snapshot.AUTO_RESTORE_FILE.read_text())
        self.assertTrue(marker["armed"])

    def test_unrequested_empty_capture_does_not_arm_stale_snapshot(self):
        self.write_snapshot(3)
        with mock.patch.object(snapshot, "save", return_value=None), \
                mock.patch.object(snapshot, "_hypr_available", return_value=True):
            snapshot.save_auto(requested=False)
        self.assertFalse(snapshot.AUTO_RESTORE_FILE.exists())

    def test_auto_restore_keeps_marker_after_failure(self):
        snapshot.AUTO_RESTORE_FILE.write_text('{"armed": true}')
        with mock.patch.object(snapshot, "restore", return_value=1):
            self.assertEqual(snapshot.restore_auto(), 1)
        self.assertTrue(snapshot.AUTO_RESTORE_FILE.exists())

    def test_auto_restore_removes_marker_only_after_success(self):
        snapshot.AUTO_RESTORE_FILE.write_text('{"armed": true}')
        with mock.patch.object(snapshot, "restore", return_value=0):
            self.assertEqual(snapshot.restore_auto(), 0)
        self.assertFalse(snapshot.AUTO_RESTORE_FILE.exists())

    def test_incomplete_restore_returns_failure(self):
        self.write_snapshot(2)
        with mock.patch.object(snapshot, "run_json", return_value=[]), \
                mock.patch.object(snapshot, "is_single_instance", return_value=False), \
                mock.patch.object(snapshot, "restore_record_argv", return_value=[]), \
                mock.patch.object(snapshot, "restore_focus"):
            self.assertEqual(snapshot._restore_impl(), 1)

    def test_complete_restore_returns_success(self):
        self.write_snapshot(2)
        process = mock.Mock(pid=1234)
        with mock.patch.object(snapshot, "run_json", return_value=[]), \
                mock.patch.object(snapshot, "is_single_instance", return_value=False), \
                mock.patch.object(snapshot, "restore_record_argv", return_value=["/usr/bin/true"]), \
                mock.patch.object(snapshot.subprocess, "Popen", return_value=process) as popen, \
                mock.patch.object(snapshot, "wait_for_client", return_value={"address": "", "workspace": {}}), \
                mock.patch.object(snapshot, "place_client"), \
                mock.patch.object(snapshot, "restore_focus"):
            self.assertEqual(snapshot._restore_impl(), 0)
        self.assertEqual(popen.call_count, 2)

    def test_systemd_units_follow_graphical_session_and_canonical_id(self):
        save_unit = (ROOT / "systemd" / "omarchy-session-snapshot-save.service").read_text()
        rolling_unit = (ROOT / "systemd" / "omarchy-session-snapshot-rolling.service").read_text()
        timer_unit = (ROOT / "systemd" / "omarchy-session-snapshot-rolling.timer").read_text()
        restore_unit = (ROOT / "systemd" / "omarchy-session-snapshot-restore.service").read_text()
        self.assertIn("PartOf=graphical-session.target", save_unit)
        self.assertIn("PartOf=graphical-session.target", timer_unit)
        self.assertIn("PartOf=graphical-session.target", restore_unit)
        self.assertIn("After=omarchy-session-snapshot-restore.service", timer_unit)
        self.assertIn("TimeoutStartSec=5min", restore_unit)
        self.assertIn("plugins/hancore.session-snapshot/", save_unit)
        self.assertIn("plugins/hancore.session-snapshot/", rolling_unit)
        self.assertIn("plugins/hancore.session-snapshot/", restore_unit)
        self.assertNotIn("plugins/omarchy-session-snapshot/", save_unit + rolling_unit + restore_unit)

    def test_login_restore_is_not_dependent_on_shell_qml(self):
        service_qml = (ROOT / "Service.qml").read_text()
        setup = (ROOT / "scripts" / "setup-systemd").read_text()
        self.assertNotIn("restore-auto", service_qml)
        self.assertIn("omarchy-session-snapshot-restore.service", setup)

    def test_progress_overlay_is_non_dismissible(self):
        overlay = (ROOT / "SessionProgressOverlay.qml").read_text()
        manifest = json.loads((ROOT / "manifest.json").read_text())
        self.assertIn("overlay", manifest["kinds"])
        self.assertEqual(manifest["entryPoints"]["overlay"], "SessionProgressOverlay.qml")
        self.assertNotIn("Cancel", overlay)
        self.assertNotIn("cancelRestore", overlay)
        self.assertIn("WlrKeyboardFocus.Exclusive", overlay)

    def test_save_progress_arms_marker(self):
        clients = [{"class": "kitty", "title": "Terminal"}]
        with mock.patch.object(snapshot, "snapshot_clients", return_value=clients), \
                mock.patch.object(snapshot, "current_focus_state", return_value={}), \
                mock.patch.object(snapshot, "launch_command"), \
                mock.patch.object(snapshot, "_notify"):
            self.assertEqual(snapshot.save_auto_progress(), 0)
        self.assertTrue(snapshot.AUTO_RESTORE_FILE.exists())
        self.assertEqual(json.loads(snapshot.LAST_FILE.read_text())["clients"], clients)

    def test_menu_action_installer_is_idempotent(self):
        menu = Path(self.tempdir.name) / "omarchy-menu.jsonc"
        menu.write_text('{\n  // existing user comments\n}\n')
        env = dict(os.environ, OMARCHY_SESSION_MENU_PATH=str(menu))
        installer = ROOT / "scripts" / "install-menu-actions"
        subprocess.run([str(installer)], env=env, check=True)
        subprocess.run([str(installer)], env=env, check=True)
        text = menu.read_text()
        self.assertEqual(text.count("hancore.session-snapshot:start"), 1)
        self.assertEqual(text.count("hancore.session-snapshot:end"), 1)
        self.assertIn('"system.logout"', text)
        self.assertIn('"system.reboot"', text)
        self.assertIn('"system.shutdown"', text)


if __name__ == "__main__":
    unittest.main()
