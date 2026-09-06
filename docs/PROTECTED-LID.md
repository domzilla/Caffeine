# Protected lid sessions

This fork adds an **experimental direct-distribution** feature for Mac laptops.
The ordinary coffee-cup toggle retains its existing behavior. The separate
**Lock & keep awake with lid closed…** action starts a protected session.

## Use

1. Build with `bash scripts/build-lid.sh` and open `dist/Caffeine Lid.app`.
   It uses a separate bundle identifier and preferences from upstream Caffeine.
   Quit the original Caffeine while using this fork: another display assertion
   or simulated mouse activity can interfere with turning the displays off.
2. Open preferences from the menu bar, choose a duration if desired, and select
   **Lock & keep awake with lid closed…**.
3. **The first session only** asks macOS to install a small privileged helper.
   Authenticate in the native macOS administrator dialog. Caffeine never reads,
   stores, or creates a password. Canceling leaves lid sleep unchanged.
4. The Mac locks immediately. After the lock is confirmed, the helper disables
   system sleep and Caffeine requests display sleep. Close the lid when the
   lock screen/display turns off. Background work can continue on battery or AC.
5. Opening the lid reveals the native lock screen. Use the account password or
   the authentication methods permitted by macOS, such as Touch ID.
   **Unlocking ends the protected session** and resumes ordinary Caffeine.
   Start a new protected session before closing the lid again.

Locking before enabling the override avoids relying on a notification after the
display has already become visible. This mode intentionally locks immediately;
it does not let you keep editing with an unlocked screen until lid closure.
It turns off external displays too. It does not shut down the Mac or log out.

## Lifetime and recovery

- Caffeine holds a short lease that it renews only while the screen is confirmed
  locked. Stop, Quit, timer expiry, unlock, or failure removes that lease.
- The helper restores normal sleep on its next poll, normally within one second.
  If Caffeine hangs, the lease expires after ten seconds. PID, UID, process start
  time, a fresh UUID, and a pending-to-locked handshake guard against stale requests.
- launchd restarts the helper after failure. A root-owned durable ownership marker
  triggers restoration after a helper crash or reboot, before accepting a session.
- A pre-existing `SleepDisabled` override is treated as a conflict and left alone.
  Avoid running other tools that change the same global setting during a session;
  macOS does not provide independent ownership of that setting for each app.
- The app ends the protected session at 10% battery on battery power, or on a
  serious/critical thermal state. Hardware protection and shutdown cannot and
  should not be overridden. Keep ventilation clear; do not run it in a closed bag.

## Helper scope

The first-use installer writes these fixed locations with administrator approval:

- `/Library/PrivilegedHelperTools/net.ziyad.caffeine.lid-helper.sh`
- `/Library/LaunchDaemons/net.ziyad.caffeine.lid-helper.plist`
- `/Library/Application Support/CaffeineLid/`

The script, plist, ownership marker, and status are root-owned. A single request
directory is owned by the installing user's numeric UID with mode 0700. The helper
accepts bounded data from that user only, validates it, and runs fixed `pmset`
commands. It never executes a client-supplied command or sources a user-writable
script. No sudoers exception is installed. Other processes running as that same
user can request the same limited power operation; this is not code-signature
authenticated IPC. The helper supports one installing account and one session.

The helper remains installed and idle between sessions, so subsequent sessions
do not require another administrator prompt. A future helper upgrade or removal
may require administrator approval. Removing the app alone does not remove the
helper. After quitting the app, uninstall it with:

```sh
sudo /bin/sh scripts/uninstall-lid-helper.sh
```

If powerd or launchd cannot restore sleep, recovery is:

```sh
sudo pmset -a disablesleep 0
```

## Build, tests, and limitations

The build script preserves the upstream Xcode project and overrides its sandbox
and bundle identifier at build time. The privileged feature requires a build
outside App Sandbox. Upstream automatic updates are disabled so they cannot
replace this fork. Builds are ad-hoc signed, not Developer ID signed or notarized.
They target macOS 14.6 or newer and include Apple Silicon and Intel code.

```sh
python3 -m unittest discover -s tests -v
bash scripts/build-lid.sh
swiftformat .
```

New UI is localized in English and Arabic; other existing languages fall back to
English for the new strings. Upstream developer guides referenced by AGENTS.md
are not included in the repository; existing style and SwiftFormat are used.

Automated tests run the actual watchdog with an isolated fake power backend;
they never change real power settings, install the helper, or lock the computer.
They cover confirmed-lock gating, stale leases, client and helper crashes,
termination, conflicting overrides, invalid input, and failed enable/restore.

Physical lid closure, panel darkness, uninterrupted work on battery/AC,
authentication on reopening, the first administrator prompt and subsequent
prompt-free sessions still require manual hardware validation. The lock operation
uses the private macOS `SACLockScreenImmediate` symbol and confirmation uses
`CGSSessionScreenIsLocked`; either can change in macOS updates. Missing lock
support or confirmation aborts the session. Successful compilation and mocked
tests do not establish hardware compatibility or a production security guarantee.

### Manual acceptance checklist

- Cancel first-use authorization: no helper and no power override.
- Approve once, stop, start again: no second administrator prompt.
- Start a background timestamp log, activate, close the lid on battery and AC:
  timestamps continue and the built-in panel is off.
- Open the lid: no desktop is exposed before authentication; unlock ends mode.
- Stop, timeout, quit, force-quit, and stop client heartbeat: `pmset -g` returns
  `SleepDisabled 0` within the documented window.
- Kill the helper during a session: launchd restarts it and restores the override.
- Reboot during a session: recovery runs, and no protected session starts itself.
- Check low battery, thermal stop, an existing external override, and uninstall.

## References

- [Apple PowerManagement implementation of pmset](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.m)
- [Apple's IOPM definitions, including lid state](https://github.com/apple-oss-distributions/IOKitUser/blob/main/pwr_mgt.subproj/IOPM.h)
- [Lock function and lock-state example](https://gist.github.com/pudquick/9797a9ce8ad97de6e326afc7c9894965)
