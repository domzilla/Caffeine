//
//  ClamshellSleepController.swift
//  Caffeine
//
//  Created by Dominic Rodemer on 26.11.26.
//

import Foundation
import IOKit.ps
import os

/// Prevents system sleep while the lid is closed (clamshell use, typically with
/// an external display), independent of the power source.
///
/// macOS offers no user-space assertion that blocks lid-close system sleep on
/// battery, so this toggles `pmset -a disablesleep` — the same mechanism
/// Amphetamine's "Power Protect" uses. Root is required. Caffeine must be
/// explicitly authorized once: on first use it asks for the administrator
/// password a single time to install its own sudoers rule
/// (/etc/sudoers.d/caffeine_PowerProtect), which grants passwordless access to
/// exactly the two pmset commands it needs. Rules installed by other apps are
/// deliberately not used: authorization must be a conscious, auditable act
/// for Caffeine itself.
///
/// Safety invariant: sleep is only disabled while silent re-enable is
/// guaranteed, so deactivation, quit, and the next launch can always restore it
/// without a password prompt.
final class ClamshellSleepController {
    static let shared = ClamshellSleepController()

    private let logger = Logger(subsystem: "net.domzilla.caffeine", category: "ClamshellSleep")

    /// Caffeine's own sudoers drop-in, installed once with administrator
    /// authorization. Other apps' rules (e.g. Amphetamine's) are not accepted.
    private static let ownSudoersFile = "/etc/sudoers.d/caffeine_PowerProtect"

    private static let sudoersContent = """
        Cmnd_Alias PMSET_CAFFEINE = /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0
        %admin ALL=(ALL) NOPASSWD: PMSET_CAFFEINE

        """

    /// Serializes all state transitions and pmset invocations
    private let queue = DispatchQueue(label: "com.caffeine.clamshell")

    /// Whether we currently hold `disablesleep 1` (only accessed on `queue`)
    private var isEngaged = false

    private var powerSourceRunLoopSource: CFRunLoopSource?

    private init() {
        self.setupPowerSourceNotifications()
    }

    deinit {
        if let source = self.powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    // MARK: - Public Methods

    /// Applies or releases sleep prevention based on the activation state and
    /// the user's lid-close preference. Fire-and-forget.
    func activationChanged(active: Bool) {
        self.queue.async {
            if active {
                guard UserDefaults.standard.bool(forKey: PreferenceKeys.preventSleepOnLidClose) else {
                    self.logger.info("Activated; lid-close prevention preference is off, nothing to do")
                    return
                }
                guard self.ensureAuthorized() else {
                    self.logger.error("Authorization failed or cancelled; reverting lid-close preference")
                    UserDefaults.standard.set(false, forKey: PreferenceKeys.preventSleepOnLidClose)
                    return
                }
                self.setSleepDisabled(true)
            } else {
                self.setSleepDisabled(false)
            }
        }
    }

    /// Handles the preference being toggled in Preferences.
    func preferenceChanged(enabled: Bool, currentlyActive: Bool) {
        self.queue.async {
            self.logger.info("Lid-close prevention preference -> \(enabled); currentlyActive=\(currentlyActive)")
            guard enabled else {
                self.setSleepDisabled(false)
                return
            }
            guard self.ensureAuthorized() else {
                self.logger.error("Authorization failed or cancelled; reverting lid-close preference")
                UserDefaults.standard.set(false, forKey: PreferenceKeys.preventSleepOnLidClose)
                return
            }
            if currentlyActive {
                self.setSleepDisabled(true)
            }
        }
    }

    /// Restores sleep if a previous run left it disabled (crash or forced
    /// quit). Runs synchronously so it is safe to call from
    /// `applicationWillTerminate`; never prompts.
    func restoreIfNeeded() {
        self.logger.debug("restoreIfNeeded called")
        self.queue.sync {
            self.setSleepDisabled(false)
        }
    }

    // MARK: - Private Methods

    /// Must be called on `queue`.
    private func setSleepDisabled(_ disabled: Bool) {
        let flagKey = PreferenceKeys.clamshellSleepDisabledByUs

        if disabled {
            // Already disabled (possibly by the user or another app): leave it
            // alone and do not claim ownership, so we never re-enable sleep
            // someone else turned off
            let current = self.currentSleepDisabled()
            guard current != true else {
                self.logger.notice("SleepDisabled already 1 (set outside Caffeine); leaving it untouched")
                return
            }
            if self.runPmset(disableSleep: true) {
                self.logger.notice("SleepDisabled 0 -> 1 (lid-close prevention engaged)")
                UserDefaults.standard.set(true, forKey: flagKey)
                self.isEngaged = true
            } else {
                self.logger.error("Failed to set disablesleep 1 via silent sudo")
            }
        } else {
            self.isEngaged = false
            guard UserDefaults.standard.bool(forKey: flagKey) else { return }
            if self.runPmset(disableSleep: false) {
                self.logger.notice("SleepDisabled 1 -> 0 (lid-close prevention released)")
                UserDefaults.standard.set(false, forKey: flagKey)
            } else {
                self.logger.error("Failed to restore disablesleep 0 via silent sudo")
            }
        }
    }

    /// Checks that Caffeine's own sudoers rule exists, installing it via a
    /// one-time administrator password prompt if missing. Rules belonging to
    /// other apps are not accepted. Must be called on `queue`.
    private func ensureAuthorized() -> Bool {
        if FileManager.default.fileExists(atPath: Self.ownSudoersFile) {
            self.logger.debug("Authorization present: \(Self.ownSudoersFile)")
            return true
        }
        self.logger.notice("Authorization missing; requesting one-time administrator password")
        let installed = self.installSudoersRule()
        if installed {
            self.logger.notice("Authorization granted: sudoers rule installed")
        } else {
            self.logger.error("Authorization denied: sudoers rule not installed")
        }
        return installed
    }

    /// Installs our sudoers drop-in via a single administrator-prompted
    /// AppleScript. Returns false when the user cancels or the install fails.
    /// Must be called on `queue`.
    private func installSudoersRule() -> Bool {
        let tempFile = NSTemporaryDirectory() + "caffeine_PowerProtect"
        guard let _ = try? Self.sudoersContent.write(toFile: tempFile, atomically: true, encoding: .utf8)
        else { return false }
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let command = "cp '\(tempFile)' '\(Self.ownSudoersFile)'"
            + " && /usr/sbin/chown root:wheel '\(Self.ownSudoersFile)'"
            + " && /bin/chmod 0440 '\(Self.ownSudoersFile)'"
        let source = "do shell script \"\(command)\" with administrator privileges"

        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            self.logger.error("Authorization prompt failed: \(error)")
        }
        return error == nil && FileManager.default.fileExists(atPath: Self.ownSudoersFile)
    }

    /// macOS on Apple Silicon clears `disablesleep` when the power source
    /// changes (AC <-> battery); the clamshell policy then powers off external
    /// displays even though the system stays awake. Observing transitions lets
    /// us re-apply the setting immediately, plus once more after a short delay
    /// in case the clear lands after the notification.
    private func setupPowerSourceNotifications() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<ClamshellSleepController>.fromOpaque(context)
                .takeUnretainedValue()
                .handlePowerSourceChange()
        }, context)?.takeRetainedValue() else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.powerSourceRunLoopSource = source
    }

    private func handlePowerSourceChange() {
        self.queue.async {
            guard self.isEngaged else { return }
            self.logger.notice("Power source changed while engaged; re-applying disablesleep 1")
            self.reapplySleepDisabled()
            self.queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.isEngaged, self.currentSleepDisabled() != true else { return }
                self.logger.notice("disablesleep was cleared during the transition; re-applying again")
                self.reapplySleepDisabled()
            }
        }
    }

    /// Must be called on `queue`.
    private func reapplySleepDisabled() {
        if self.runPmset(disableSleep: true) {
            self.logger.notice("disablesleep re-applied after power source change")
        } else {
            self.logger.error("Failed to re-apply disablesleep after power source change")
        }
    }

    /// Reads the current SleepDisabled state from `pmset -g`.
    /// Must be called on `queue`.
    private func currentSleepDisabled() -> Bool? {
        guard let output = self.runProcess("/usr/bin/pmset", ["-g"]) else { return nil }
        for line in output.split(separator: "\n") where line.hasPrefix("SleepDisabled") {
            return line.split(whereSeparator: { $0 == " " || $0 == "\t" }).last == "1"
        }
        return nil
    }

    /// Toggles sleep via passwordless sudo. Must be called on `queue`.
    private func runPmset(disableSleep: Bool) -> Bool {
        self.runProcess(
            "/usr/bin/sudo",
            ["-n", "/usr/bin/pmset", "-a", "disablesleep", disableSleep ? "1" : "0"]
        ) != nil
    }

    /// Runs a process and returns stdout on exit code 0, nil otherwise.
    private func runProcess(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        return String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}
