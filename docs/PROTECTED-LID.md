# Automatic lid control

This direct-distribution fork couples lid behavior to the normal Caffeine toggle.
The **Automatic lid control** checkbox enables this behavior and defaults to on.
Unchecking it keeps ordinary Caffeine active without lid handling. There is no
separate session button, and activation never requests a lock.

## Behavior

| Event while Caffeine is active | Result |
| --- | --- |
| Activate with the lid open | Arm monitoring and prevent system sleep; stay unlocked |
| Close the lid | Set built-in screen brightness and keyboard backlight to zero; remain awake without requesting a lock |
| Open the lid | Request the native macOS lock immediately, then restore both saved brightness levels after stable lock confirmation |
| Authenticate | Caffeine remains active; the next lid cycle works automatically |
| Deactivate, timer expires, or quit | Release the helper lease and restore ordinary sleep/brightness |

The user's existing Mac login credentials apply; Caffeine never creates, reads,
or stores a password. macOS may allow Touch ID or other configured authentication.
Manual locking and managed security policies are not overridden or undone.

## Installation and usage

Build with `bash scripts/build-lid.sh`, open `dist/Caffeine Lid.app`, and activate
Caffeine using the menu-bar cup with the **Automatic lid control** checkbox enabled. Wait for the brief
**Preparing…** message to disappear before testing the lid. First activation
installs a limited helper using the native administrator dialog. Version-1
installations need administrator approval once to install the corrected version-2
helper. Later activations reuse version 2 without another administrator prompt.

Quit other keep-awake/brightness utilities while testing. This fork has its own
bundle identifier `net.ziyad.caffeine.lid` and does not accept upstream auto-updates.
The build is universal (Apple Silicon and Intel), targets macOS 14.6+, and is ad-hoc
signed, not Developer ID signed or notarized. Build outside App Sandbox using the
provided script; the upstream Xcode project is intentionally unchanged.

## How it works

- A continuous `PreventUserIdleDisplaySleep` assertion avoids the upstream
  assertion's two-second gap. Screen darkness is brightness zero, not display
  sleep, so the normal display-sleep/password trigger is not intentionally invoked.
- `IOPMrootDomain` lid-change notifications run on the main queue; their event
  bitfield drives close/open transitions directly. A 250 ms poll catches missed
  notifications. Duplicate events never relock an already open laptop.
- The built-in display uses `DisplayServicesGetBrightness/SetBrightness`.
  The built-in keyboard uses `KeyboardBrightnessClient` from CoreBrightness.
  Current levels are remembered while open and reapplied after confirmed locking.
  Zero brightness is reasserted once per second while closed. External monitors
  are not dimmed; native locking still locks the session across all displays.
- During a closed-lid session, periodic IOKit user-activity assertions postpone
  idle behavior. Synthetic mouse activity from the optional Keep apps active
  feature is suppressed while the lid is closed.
- Closing also paints an opaque, non-activating black cover over the internal
  display before it can wake again. This cover does not authenticate or lock the
  session; background work continues unlocked as requested.
- Opening calls `SACLockScreenImmediate`. The cover stays in place and brightness
  zero is reasserted every 50 ms while `CGSSessionScreenIsLocked` is checked.
  Confirmation must stay true for 750 ms with the lid open before brightness is
  restored behind the cover and the cover is removed. Unknown/false lock state or
  reclosure resets that interval. Timeout never reveals an unlocked desktop;
  late confirmation can still recover. If the private lock service fails entirely,
  quitting Caffeine (for example from another display) or restarting the Mac
  removes the cover. No lock is requested on closing.

macOS controls the timing of panel power and lock-screen presentation. This is
**not a guarantee that zero pixels can ever be visible before locking on every
Mac or OS version**. Notification/brightness/lock APIs and hardware ordering need
physical validation. Unlike locking before closure, this requested behavior leaves
an unlocked session running while the lid is closed. Private Apple interfaces may
change, and organizational security policy can enforce independent locking.

## Power helper and recovery

The first-use installer writes fixed root-owned locations:

- `/Library/PrivilegedHelperTools/net.ziyad.caffeine.lid-helper.sh`
- `/Library/LaunchDaemons/net.ziyad.caffeine.lid-helper.plist`
- `/Library/Application Support/CaffeineLid/`

Only the installing UID may write the request directory (mode 0700). Requests are
bounded data, never commands. The helper validates UID, PID/start identity, UUID,
freshness and a two-step handshake, then runs fixed `pmset` operations. The wire
opcode `locked` is the historical version-1 name for **activate the power override**;
it does not ask the helper to lock the screen or attest to lock state. Keeping that
wire format remains unchanged in version 2, which fixes heartbeat validation and
publishes status by atomic replacement so readers cannot see a partial value.
No sudoers exception or stored password is used. This IPC authorizes the installing
user, not a specific code signature; other processes under that UID can request
this same limited power operation. Only one installing account/session is supported.

The helper normally restores sleep within one poll (about one second) after lease
removal. A stopped heartbeat loses its lease after ten seconds. Renewal runs once
per second on a serial utility queue, independently of the UI loop and brightness
calls. A scoped process activity prevents App Nap during the session. Stopping
drains any in-flight renewal before removing the lease, so a queued callback cannot
recreate it. The helper samples the lease timestamp before reading the clock:
sampling in the opposite order could reject a valid concurrent renewal at a second
boundary as future-dated. Stale and truly future-dated requests remain invalid.
launchd restarts the
helper after a crash; a durable ownership marker restores this helper's override
before accepting new sessions, including after a reboot. An external pre-existing
SleepDisabled override is preserved and reported as a conflict. Avoid other apps
that change the same global setting mid-session, as macOS exposes no per-app ownership.

The app stops at 10% battery while unplugged or a serious/critical thermal state.
Brightness zero reduces lighting power; the running CPU still consumes more energy
than sleep. Do not run the laptop in a closed bag; keep ventilation clear.

After quitting Caffeine, remove the persistent helper with:

```sh
sudo /bin/sh scripts/uninstall-lid-helper.sh
```

Emergency power recovery, if launchd/powerd is unavailable:

```sh
sudo pmset -a disablesleep 0
```

The helper is deliberately idle between sessions and is not removed by deleting
the application alone. A future helper upgrade/removal can require administrator
approval; ordinary toggling does not.

## Validation

```sh
python3 -m unittest discover -s tests -v
swiftc src/Caffeine/Classes/Models/LockRevealGate.swift tests/LockRevealTests.swift -o /tmp/caffeine-reveal-tests
/tmp/caffeine-reveal-tests
swiftc src/Caffeine/Classes/Models/LidCycleState.swift tests/LidCycleTests.swift -o /tmp/caffeine-lid-tests
/tmp/caffeine-lid-tests
bash scripts/build-lid.sh
swiftformat .
```

The 19 isolated watchdog/client tests cover heartbeat expiration, client/helper
crashes, failed enable/restore, conflicts and untrusted request data. The actual
Swift client is also tested against the helper for rapid off/on cycles and
cancellation during startup; restarts wait for prior-session cleanup. A regression
test renews between the helper's timestamp and clock reads, and another blocks the
Swift main actor for 13 seconds (longer than the ten-second lease) while verifying
that the background heartbeat remains active. The transition
suite covers activation without locking, close without locking, open with locking,
confirmation-before-brightness restoration, repeated events, successive cycles and
rapid reclosure while locking. Neither suite closes the physical lid or locks the
user's actual session. Read-only probes confirmed display-brightness and keyboard
backlight interfaces are available on the development Mac.

Manual acceptance requires closing/opening the lid on battery and AC, observing
both lights go off while a background job continues, verifying authentication is
required on reopening, and repeating the cycle after unlocking. Also verify that
an extended closed-lid session does not trigger independent idle locking and that
the former brightness levels return. Hardware checks cannot be substituted by a
successful build. New strings are localized in Arabic and English; other languages
fall back to English for this feature.

## References

- [Apple pmset implementation](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.m)
- [Apple IOPM API](https://github.com/opensource-apple/IOKitUser/blob/master/pwr_mgt.subproj/IOPMLib.h)
- [DisplayServices brightness implementation example](https://github.com/nriley/brightness/blob/master/brightness.c)
- [KeyboardBrightnessClient method signatures](https://github.com/rakalex/mac-brightnessctl/blob/master/KeyboardBrightnessClient.h)
