import AppKit
import Combine
import IOKit
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
    private let helperSession = LidHelperSession()
    private var monitor: Task<Void, Never>?
    private var lockTask: Task<Void, Never>?
    private var lockRequestID: UUID?
    private var cycle = LidCycleState()
    private let display = BuiltInDisplay()
    private let privacyShield = LidPrivacyShield()
    private let keyboard = KeyboardBacklight()
    private var lidMonitor: LidMonitor?
    private var activityID: IOPMAssertionID = 0
    private var lastActivity = Date.distantPast
    private let loginLibrary = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY)
    private let helperDirectory = URL(fileURLWithPath: "/Library/Application Support/CaffeineLid", isDirectory: true)

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
        self.privacyShield.prepare()
        let id = UUID()
        self.sessionID = id
        self.isPreparing = true
        // Monitor before enabling the override: no close/open transition during
        // administrator approval or helper startup is silently discarded.
        if self.lidMonitor == nil, !self.cycle.lockPending {
            self.cycle = LidCycleState()
        }
        let watcher = LidMonitor { [weak self] closed in self?.handleLid(closed) }
        guard watcher.start() else {
            self.fail(String(localized: "Automatic lid control is unavailable on this Mac. Caffeine was deactivated."))
            return
        }
        self.lidMonitor?.stop()
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
            try await self.helperSession.start(id: id) { self.helperIsInstalled() }
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
                    if self.cycle.lockPending {
                        self.darkenLights()
                    }
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
                        do { try self.helperSession.checkHealth() } catch { self.fail()
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

    func stop(preservingLidPrivacy: Bool = false) {
        let keepPrivacy = preservingLidPrivacy && (self.cycle.closed || self.cycle.lockPending)
        self.sessionID = nil
        self.monitor?.cancel()
        self.monitor = nil
        if !keepPrivacy {
            self.lidMonitor?.stop()
            self.lidMonitor = nil
        }
        self.helperSession.stop()
        self.isPreparing = false
        self.isRunning = false
        if self.activityID != 0 {
            IOPMAssertionRelease(self.activityID)
            self.activityID = 0
        }
        // A lock already requested on opening must finish before making the
        // desktop visible, even when a timeout/stop races with that opening.
        if !keepPrivacy, !self.cycle.lockPending || self.cycle.closed {
            self.lockTask?.cancel()
            self.lockRequestID = nil
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
            self.lockTask?.cancel()
            self.lockRequestID = nil
            // Paint black while the lid closes, before the next wake can show
            // desktop pixels even if macOS resets hardware brightness itself.
            self.privacyShield.show()
            self.darkenLights()
        case .lock:
            self.privacyShield.show()
            self.darkenLights()
            self.lockFunction?()
            self.lockTask?.cancel()
            let requestID = UUID()
            self.lockRequestID = requestID
            self.lockTask = Task { [weak self] in
                var revealGate = LockRevealGate()
                var attempt = 0
                while !Task.isCancelled {
                    guard let self, !Task.isCancelled, self.lockRequestID == requestID else { return }
                    // Hardware/ambient brightness may be reapplied during wake.
                    // Continue forcing zero throughout the lock transition.
                    self.darkenLights()
                    let lidClosed = LidMonitor.readClosed() ?? true
                    if
                        revealGate.canReveal(
                            locked: Self.isScreenLocked(), lidClosed: lidClosed,
                            now: ProcessInfo.processInfo.systemUptime
                        )
                    {
                        if self.cycle.confirmLock() {
                            self.restoreLights()
                            if !self.isEngaged {
                                self.lidMonitor?.stop()
                                self.lidMonitor = nil
                            }
                        }
                        self.lockRequestID = nil
                        return
                    }
                    if attempt > 0, attempt % 20 == 0, Self.isScreenLocked() != true {
                        self.lockFunction?()
                    }
                    if attempt == 150 {
                        // Keep observing after the warning: a late valid lock
                        // may recover, but elapsed time alone never reveals.
                        self
                            .errorMessage =
                            String(
                                localized: "Waiting for macOS to confirm locking. The screen remains covered for privacy."
                            )
                    }
                    attempt += 1
                    do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                }
            }
        }
    }

    private func darkenLights() {
        self.display.darken()
        self.keyboard.darken()
    }

    private func restoreLights() {
        // Raise the backlights behind the cover; only then uncover the secure
        // lock screen (or complete an explicit stop outside a pending lock).
        self.display.restore()
        self.keyboard.restore()
        self.privacyShield.hide()
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

    private func helperIsInstalled() -> Bool {
        let owner = try? String(contentsOf: self.helperDirectory.appendingPathComponent("owner"), encoding: .utf8)
        let version = try? String(contentsOf: self.helperDirectory.appendingPathComponent("version"), encoding: .utf8)
        return owner == String(getuid()) && version == "2"
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

    private enum LidError: Error { case unavailable }
}
