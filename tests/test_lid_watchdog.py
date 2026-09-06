"""Run the actual watchdog with a fake pmset and isolated state directory.

No administrator access, power changes, screen locking, or installed helpers.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

SOURCE = Path(__file__).resolve().parents[1] / "src/Caffeine/Resources/protected-lid-watchdog.sh"
NONCE = "12345678-1234-1234-1234-123456789ABC"


class WatchdogTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="caffeine test '")
        self.root = Path(self.temp.name)
        self.state = self.root / "state"
        self.state.mkdir()
        (self.state / "request").mkdir()
        self.lease = self.state / "request/lease"
        self.power = self.root / "power"
        self.power.write_text("0")
        self.calls = self.root / "calls"
        self.calls.touch()
        self.failure = self.root / "fail-enable"
        self.restore_failure = self.root / "fail-restore-once"
        self.mock = self.root / "pmset"
        # Quote paths independently of the code under test, including apostrophes.
        import shlex
        q = shlex.quote
        self.mock.write_text(f'''#!/bin/sh
if [ "$1" = -g ]; then
    printf 'System-wide power settings:\\n SleepDisabled %s\\n' "$(cat {q(str(self.power))})"
else
    echo "$*" >> {q(str(self.calls))}
    if [ "$3" = 1 ] && [ -f {q(str(self.failure))} ]; then exit 1; fi
    if [ "$3" = 0 ] && [ -f {q(str(self.restore_failure))} ]; then
        rm {q(str(self.restore_failure))}; exit 1
    fi
    echo "$3" > {q(str(self.power))}
fi
''')
        self.mock.chmod(0o700)
        # Production has fixed absolute paths; only this isolated test copy uses mocks.
        self.script = SOURCE.read_text().replace(
            "state='/Library/Application Support/CaffeineLid'", "state=" + q(str(self.state))
        ).replace("/usr/bin/pmset", q(str(self.mock)))
        self.processes = []

    def tearDown(self):
        self.lease.unlink(missing_ok=True)
        for process in self.processes:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=8)
        self.temp.cleanup()

    def launch(self, value="pending", pid=None, nonce=NONCE):
        self.client_pid = pid or os.getpid()
        process = subprocess.Popen(
            ["/bin/sh", "-c", self.script, "--", str(os.getuid())],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        self.processes.append(process)
        self.wait_for(lambda: self.status() == "idle")
        self.lease.write_text(f"{value}:{self.client_pid}:{nonce}")
        return process

    def wait_for(self, predicate):
        deadline = time.monotonic() + 7
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.05)
        self.fail("watchdog did not reach expected state")

    def status(self):
        try:
            return (self.state / "status").read_text()
        except FileNotFoundError:
            return None

    def active(self):
        process = self.launch()
        self.wait_for(lambda: self.status() == f"ready:{NONCE}")
        self.lease.write_text(f"locked:{self.client_pid}:{NONCE}")
        self.wait_for(lambda: self.status() == f"active:{NONCE}")
        self.assertEqual(self.power.read_text().strip(), "1")
        return process

    def assert_restored(self, process):
        self.wait_for(lambda: self.status() in ("idle", "offline") and self.power.read_text().strip() == "0")
        self.assertFalse((self.state / "owned").exists())

    def test_swift_client_rapid_off_on_and_cancelled_start(self):
        repo = SOURCE.parents[3]
        executable = self.root / "session-tests"
        subprocess.run([
            "swiftc", str(repo / "src/Caffeine/Classes/Models/LidHelperSession.swift"),
            str(repo / "src/Caffeine/Classes/Models/LidLeaseHeartbeat.swift"),
            str(repo / "tests/LidHelperSessionTests.swift"), "-o", str(executable),
        ], check=True, capture_output=True, text=True)
        helper = subprocess.Popen(
            ["/bin/sh", "-c", self.script, "--", str(os.getuid())],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        self.processes.append(helper)
        self.wait_for(lambda: self.status() == "idle")
        result = subprocess.run([str(executable), str(self.state), "block-main-actor"], capture_output=True, text=True, timeout=65)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("regression tests passed", result.stdout)
        self.assert_restored(helper)

    def test_renewal_between_clock_and_timestamp_reads_stays_active(self):
        # Emulate a legitimate renewal crossing a second boundary after date
        # sampled the clock but before the old helper reads the lease timestamp.
        import shlex
        trigger = self.root / "renew-during-clock-read"
        clock = self.root / "clock"
        clock.write_text(f'''#!/bin/sh
now=$(/bin/date +%s)
if [ -f {shlex.quote(str(trigger))} ]; then
    /usr/bin/touch -t "$(/bin/date -r "$((now + 1))" +%Y%m%d%H%M.%S)" {shlex.quote(str(self.lease))}
fi
printf '%s\\n' "$now"
''')
        clock.chmod(0o700)
        self.script = self.script.replace("/bin/date +%s", shlex.quote(str(clock)))
        process = self.active()
        trigger.touch()
        time.sleep(4)
        self.assertEqual(self.status(), f"active:{NONCE}")
        self.assertEqual(self.calls.read_text().splitlines(), ["-a disablesleep 1"])
        trigger.unlink()
        self.lease.unlink()
        self.assert_restored(process)

    def test_pending_does_not_change_power(self):
        process = self.launch()
        self.wait_for(lambda: self.status() == f"ready:{NONCE}")
        self.assertEqual(self.calls.read_text(), "")
        self.lease.unlink()
        self.assert_restored(process)

    def test_confirmed_lock_then_stop_restores_sleep(self):
        process = self.active()
        self.lease.unlink()
        self.assert_restored(process)
        self.assertEqual(self.calls.read_text().splitlines(), ["-a disablesleep 1", "-a disablesleep 0"])

    def test_expired_heartbeat_restores_sleep(self):
        process = self.active()
        old = time.time() - 60
        os.utime(self.lease, (old, old))
        self.assert_restored(process)

    def test_unlock_cannot_leave_override_active(self):
        process = self.active()
        self.lease.write_text(f"pending:{self.client_pid}:{NONCE}")
        self.assert_restored(process)

    def test_wrong_nonce_restores_sleep(self):
        process = self.active()
        self.lease.write_text("locked:DIFFERENT")
        self.assert_restored(process)

    def test_existing_override_is_not_overwritten(self):
        self.power.write_text("1")
        process = self.launch()
        self.wait_for(lambda: self.status() == f"conflict:{NONCE}")
        self.assertEqual(self.calls.read_text(), "")
        self.assertEqual(self.power.read_text(), "1")
        process.terminate()
        process.wait(timeout=8)
        self.assertEqual(self.power.read_text(), "1")

    def test_override_during_lock_preparation_is_preserved(self):
        self.launch()
        self.wait_for(lambda: self.status() == f"ready:{NONCE}")
        self.power.write_text("1")
        self.lease.write_text(f"locked:{self.client_pid}:{NONCE}")
        self.wait_for(lambda: self.status() == f"conflict:{NONCE}")
        self.assertEqual(self.calls.read_text(), "")
        self.assertFalse((self.state / "owned").exists())

    def test_second_nonce_ends_old_session_before_new_one(self):
        process = self.active()
        second = "AAAAAAAA-1234-1234-1234-123456789ABC"
        self.lease.write_text(f"pending:{self.client_pid}:{second}")
        self.wait_for(lambda: self.status() == f"ready:{second}")
        self.assertEqual(self.power.read_text().strip(), "0")
        self.lease.unlink()
        self.assert_restored(process)

    def test_failed_enable_rolls_back(self):
        self.failure.touch()
        process = self.launch()
        self.wait_for(lambda: self.status() == f"ready:{NONCE}")
        self.lease.write_text(f"locked:{self.client_pid}:{NONCE}")
        self.wait_for(lambda: self.status() == f"failed:{NONCE}")
        self.assertEqual(self.power.read_text().strip(), "0")
        self.assertIn("-a disablesleep 0", self.calls.read_text())

    def test_failed_restore_is_retried(self):
        process = self.active()
        self.restore_failure.touch()
        self.lease.unlink()
        self.assert_restored(process)
        self.assertEqual(self.calls.read_text().count("-a disablesleep 0"), 2)

    def test_termination_restores_sleep(self):
        process = self.active()
        process.terminate()
        self.assert_restored(process)

    def test_app_crash_restores_sleep(self):
        app = subprocess.Popen(["/bin/sleep", "60"])
        self.processes.append(app)
        process = self.launch(pid=app.pid)
        self.wait_for(lambda: self.status() == f"ready:{NONCE}")
        self.lease.write_text(f"locked:{app.pid}:{NONCE}")
        self.wait_for(lambda: self.status() == f"active:{NONCE}")
        app.kill()
        app.wait()
        self.assert_restored(process)

    def test_stale_lease_never_enables_sleep_override(self):
        process = self.launch()
        self.wait_for(lambda: self.status() == f"ready:{NONCE}")
        self.lease.write_text(f"locked:{self.client_pid}:{NONCE}")
        old = time.time() - 60
        os.utime(self.lease, (old, old))
        self.assert_restored(process)
        self.assertEqual(self.calls.read_text(), "")

    def test_future_dated_heartbeat_restores_sleep(self):
        process = self.active()
        future = time.time() + 60
        os.utime(self.lease, (future, future))
        self.assert_restored(process)

    def test_invalid_pid_is_never_executed(self):
        self.launch(pid="1; touch /tmp/should-not-exist")
        time.sleep(1.5)
        self.assertEqual(self.status(), "idle")
        self.assertEqual(self.calls.read_text(), "")

    def test_helper_crash_recovers_durable_override(self):
        process = self.active()
        process.kill()
        process.wait()
        self.assertTrue((self.state / "owned").exists())
        self.lease.unlink()
        restarted = self.launch()
        self.wait_for(lambda: self.power.read_text().strip() == "0")
        self.assertFalse((self.state / "owned").exists())
        self.lease.unlink()
        self.assert_restored(restarted)

    def test_locked_request_without_handshake_is_rejected(self):
        self.launch("locked")
        time.sleep(1.5)
        self.assertEqual(self.status(), "idle")
        self.assertEqual(self.calls.read_text(), "")


if __name__ == "__main__":
    unittest.main()
