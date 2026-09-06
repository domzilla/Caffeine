import AppKit
import Combine
import IOKit
import IOKit.ps
import IOKit.pwr_mgt

/// Watches every lid cycle while Caffeine is active. Closing only darkens the
/// built-in panel. Opening requests the native lock before restoring brightness.
@MainActor
final class AutomaticLidManager: ObservableObject {
    @Published private(set) var isPreparing = false
    @Published private(set) var isRunning = false
    @Published private(set) var isLidClosed = false
    @Published var errorMessage: String?
    var didFail: (() -> Void)?

    private var sessionID: UUID?
    private var leaseURL: URL?
    private var monitor: Task<Void, Never>?
    private var lockTask: Task<Void, Never>?
    private var cycle = LidCycleState()
    private let display = BuiltInDisplay()
    private let keyboard = KeyboardBacklight()
    private var lidMonitor: LidMonitor?
    private var activityID: IOPMAssertionID = 0
    private var lastActivity = Date.distantPast
    private let loginLibrary = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY)
    private let helperDirectory = URL(fileURLWithPath: "/Library/Application Support/CaffeineLid", isDirectory: true)
    private var statusURL: URL {
        self.helperDirectory.appendingPathComponent("status")
    }

    var isEngaged: Bool {
        self.isPreparing || self.isRunning
    }

    func start() async {
        guard !self.isEngaged else { return }
        self.errorMessage = nil
        guard
            let closed = LidMonitor.readClosed(), self.lockFunction != nil,
            self.display.prepare() else
        {
            self.fail(String(localized: "Automatic lid control is unavailable on this Mac. Caffeine was deactivated."))
            return
        }
        if !self.keyboard.prepare() {
            self
                .errorMessage =
                String(
                    localized: "Keyboard backlight control is unavailable on this Mac; automatic display and lid control will still work."
                )
        }
        let id = UUID()
        self.sessionID = id
        self.isPreparing = true
        // Monitor before enabling the override: no close/open transition during
        // administrator approval or helper startup is silently discarded.
        self.cycle = LidCycleState()
        let watcher = LidMonitor { [weak self] closed in self?.handleLid(closed) }
        guard watcher.start() else {
            self.fail(String(localized: "Automatic lid control is unavailable on this Mac. Caffeine was deactivated."))
            return
        }
        self.lidMonitor = watcher
        self.handleLid(closed)
        do {
            if !self.helperIsInstalled() {
                guard let scriptURL = Bundle.main.url(forResource: "protected-lid-watchdog", withExtension: "sh") else {
                    throw LidError.unavailable
                }
                try await Self.authorize(Self.installCommand(script: String(contentsOf: scriptURL, encoding: .utf8)))
            }
            guard self.sessionID == id else { return }
            for _ in 0..<50 {
                if self.helperIsInstalled(), let status = self.readStatus(), status != "offline" {
                    break
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard
                self.helperIsInstalled(), let status = self.readStatus(), status != "offline",
                !status.hasPrefix("active:"), !status.hasPrefix("ready:") else { throw LidError.unavailable }
            self.leaseURL = self.helperDirectory.appendingPathComponent("request/lease")
            try self.refreshLease(allowOverride: false)
            try await self.waitForStatus("ready", id: id)
            // The helper only manages power. No lock is requested at activation.
            try self.refreshLease(allowOverride: true)
            try await self.waitForStatus("active", id: id)
            guard self.sessionID == id else { return }
            self.isPreparing = false
            self.isRunning = true
            self.monitor = Task { [weak self] in
                var heartbeat = Date.distantPast
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                    guard let self, self.sessionID == id else { return }
                    guard let closed = LidMonitor.readClosed() else { self.fail()
                        return
                    }
                    self.handleLid(closed) // Fallback for dropped IOKit notifications.
                    if Date().timeIntervalSince(heartbeat) >= 1 {
                        if closed {
                            // Keep the logical display awake and prevent idle lock;
                            // darkness is brightness=0, never display sleep.
                            if Date().timeIntervalSince(self.lastActivity) >= 20, Self.isScreenLocked() != true {
                                IOPMAssertionDeclareUserActivity(
                                    "Caffeine closed lid" as CFString,
                                    kIOPMUserActiveLocal,
                                    &self.activityID
                                )
                                self.lastActivity = Date()
                            }
                            self.darkenLights()
                        } else if !self.cycle.lockPending {
                            self.display.rememberBrightness()
                            self.keyboard.rememberBrightness()
                        }
                        guard self.readStatus() == "active:\(id.uuidString)" else { self.fail()
                            return
                        }
                        if Self.shouldStopForPower() {
                            self
                                .fail(
                                    String(
                                        localized: "Caffeine stopped because the battery is low or the Mac is too warm."
                                    )
                                )
                            return
                        }
                        do { try self.refreshLease(allowOverride: true) } catch { self.fail()
                            return
                        }
                        heartbeat = Date()
                    }
                }
            }
        } catch {
            guard self.sessionID == id else { return }
            self.fail()
        }
    }

    func stop() {
        let oldID = self.sessionID
        self.sessionID = nil
        self.monitor?.cancel()
        self.monitor = nil
        self.lidMonitor?.stop()
        self.lidMonitor = nil
        if
            let leaseURL, let oldID,
            let value = try? String(contentsOf: leaseURL, encoding: .utf8), value.hasSuffix(":" + oldID.uuidString)
        {
            try? FileManager.default.removeItem(at: leaseURL)
        }
        self.leaseURL = nil
        self.isPreparing = false
        self.isRunning = false
        if self.activityID != 0 {
            IOPMAssertionRelease(self.activityID)
            self.activityID = 0
        }
        // A lock already requested on opening must finish before making the
        // desktop visible, even when a timeout/stop races with that opening.
        if !self.cycle.lockPending {
            self.restoreLights()
        }
    }

    private func handleLid(_ closed: Bool) {
        if self.isLidClosed != closed {
            self.isLidClosed = closed
        }
        guard let action = self.cycle.update(closed: closed) else { return }
        switch action {
        case .darken:
            self.darkenLights()
        case .lock:
            // Called directly on the main queue by the IOKit callback.
            self.darkenLights()
            self.lockFunction?()
            self.lockTask?.cancel()
            self.lockTask = Task { [weak self] in
                for attempt in 0..<100 {
                    guard let self, !Task.isCancelled else { return }
                    if Self.isScreenLocked() == true {
                        if self.cycle.confirmLock() {
                            self.restoreLights()
                        }
                        return
                    }
                    if attempt > 0, attempt % 10 == 0 {
                        self.lockFunction?()
                    }
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                }
                // Do not reveal an unlocked desktop if native locking failed.
                self?
                    .errorMessage =
                    String(
                        localized: "macOS did not confirm the lock. The screen remains dark. Use the brightness keys if you need to recover the display."
                    )
            }
        }
    }

    private func darkenLights() {
        self.display.darken()
        self.keyboard.darken()
    }

    private func restoreLights() {
        self.display.restore()
        self.keyboard.restore()
    }

    private typealias LockFunction = @convention(c) () -> Void
    private var lockFunction: LockFunction? {
        guard let library = self.loginLibrary, let symbol = dlsym(library, "SACLockScreenImmediate") else { return nil }
        return unsafeBitCast(symbol, to: LockFunction.self)
    }

    private func fail(_ message: String? = nil) {
        self.stop()
        self
            .errorMessage = message ??
            String(
                localized: "Automatic lid control could not start or stopped responding. Caffeine was deactivated. Check the administrator request and other sleep-control apps, then try again."
            )
        self.didFail?()
    }

    private func refreshLease(allowOverride: Bool) throws {
        guard let leaseURL, let sessionID else { throw LidError.unavailable }
        // "locked" is the legacy v1 helper's activation opcode. Reusing its
        // power-only protocol avoids another administrator installation prompt.
        let value = "\(allowOverride ? "locked" : "pending"):\(ProcessInfo.processInfo.processIdentifier):\(sessionID.uuidString)"
        try value.write(to: leaseURL, atomically: true, encoding: .utf8)
    }

    private func readStatus() -> String? {
        try? String(contentsOf: self.statusURL, encoding: .utf8)
    }

    private func waitForStatus(_ status: String, id: UUID) async throws {
        for _ in 0..<50 {
            guard self.sessionID == id else { throw CancellationError() }
            if self.readStatus() == "\(status):\(id.uuidString)" {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw LidError.unavailable
    }

    private func helperIsInstalled() -> Bool {
        let owner = try? String(contentsOf: self.helperDirectory.appendingPathComponent("owner"), encoding: .utf8)
        let version = try? String(contentsOf: self.helperDirectory.appendingPathComponent("version"), encoding: .utf8)
        return owner == String(getuid()) && version == "1"
    }

    private nonisolated static func installCommand(script: String) -> String {
        let uid = getuid()
        let label = "net.ziyad.caffeine.lid-helper"
        let helper = "/Library/PrivilegedHelperTools/" + label + ".sh"
        let plist = "/Library/LaunchDaemons/" + label + ".plist"
        let configuration = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Label</key><string>\(label)</string>
        <key>ProgramArguments</key><array><string>/bin/sh</string><string>\(helper)</string><string>\(uid)</string></array>
        <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
        <key>ThrottleInterval</key><integer>5</integer>
        <key>ProcessType</key><string>Background</string>
        </dict></plist>
        """
        // Every destination is fixed and root-owned; only a numeric UID and
        // the bundled script/plist are inserted, with POSIX shell quoting.
        return """
        set -eu
        state='/Library/Application Support/CaffeineLid'
        if [ -f "$state/owner" ] && [ "$(/bin/cat "$state/owner")" != '\(uid)' ]; then exit 1; fi
        /bin/mkdir -p /Library/PrivilegedHelperTools /Library/LaunchDaemons "$state"
        /usr/sbin/chown root:wheel "$state"
        /bin/chmod 755 "$state"
        /bin/launchctl bootout system/\(label) 2>/dev/null || true
        /bin/mkdir -p "$state/request"
        /usr/sbin/chown \(uid) "$state/request"
        /bin/chmod 700 "$state/request"
        /usr/bin/printf '%s' \(Self.shellQuote(script)) > \(Self.shellQuote(helper))
        /usr/bin/printf '%s' \(Self.shellQuote(configuration)) > \(Self.shellQuote(plist))
        /usr/sbin/chown root:wheel \(Self.shellQuote(helper)) \(Self.shellQuote(plist))
        /bin/chmod 755 \(Self.shellQuote(helper))
        /bin/chmod 644 \(Self.shellQuote(plist))
        /bin/launchctl bootstrap system \(Self.shellQuote(plist))
        """
    }

    private nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private nonisolated static func authorize(_ command: String) async throws {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw LidError.unavailable }
        }.value
    }

    private static func isScreenLocked() -> Bool? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
        return session["CGSSessionScreenIsLocked"] as? Bool
    }

    private static func shouldStopForPower() -> Bool {
        if [.serious, .critical].contains(ProcessInfo.processInfo.thermalState) {
            return true
        }
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        for source in sources {
            guard
                let values = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                values[kIOPSTransportTypeKey] as? String == kIOPSInternalType,
                values[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
                let current = values[kIOPSCurrentCapacityKey] as? Int,
                let maximum = values[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            if Double(current) / Double(maximum) <= 0.10 {
                return true
            }
        }
        return false
    }

    private enum LidError: Error { case unavailable }
}
