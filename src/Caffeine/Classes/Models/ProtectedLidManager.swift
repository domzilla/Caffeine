import AppKit
import Combine
import IOKit
import IOKit.ps

/// A protected session is locked BEFORE lid sleep is disabled. It ends on
/// authentication, so opening the lid can never expose an unlocked desktop.
@MainActor
final class ProtectedLidManager: ObservableObject {
    @Published private(set) var isPreparing = false
    @Published private(set) var isRunning = false
    @Published var errorMessage: String?
    var didStop: (() -> Void)?

    private var sessionID: UUID?
    private var leaseURL: URL?
    private var monitor: Task<Void, Never>?
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
        guard Self.lidIsClosed() != nil else {
            self.errorMessage = String(localized: "Protected lid mode requires a Mac laptop.")
            self.didStop?()
            return
        }
        guard
            let library = self.loginLibrary,
            let symbol = dlsym(library, "SACLockScreenImmediate") else
        {
            self
                .errorMessage =
                String(localized: "The macOS lock service is unavailable. Protected lid mode was not enabled.")
            self.didStop?()
            return
        }
        let id = UUID()
        self.sessionID = id
        self.isPreparing = true
        do {
            if !self.helperIsInstalled() {
                guard let scriptURL = Bundle.main.url(forResource: "protected-lid-watchdog", withExtension: "sh") else {
                    throw LidError.unavailable
                }
                let script = try String(contentsOf: scriptURL, encoding: .utf8)
                try await Self.authorize(Self.installCommand(script: script))
            }
            guard self.sessionID == id else { return }
            // An existing session belongs to another running copy of Caffeine.
            for _ in 0..<50 {
                let status = self.readStatus()
                if self.helperIsInstalled(), status != nil, status != "offline" {
                    break
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard
                self.helperIsInstalled(),
                let status = self.readStatus(), status != "offline",
                !status.hasPrefix("active:"), !status.hasPrefix("ready:") else
            {
                throw LidError.unavailable
            }
            self.leaseURL = self.helperDirectory.appendingPathComponent("request/lease")
            try self.refreshLease(locked: false)
            try await self.waitForStatus("ready", id: id)
            guard self.sessionID == id else { return }

            typealias LockFunction = @convention(c) () -> Void
            let lock = unsafeBitCast(symbol, to: LockFunction.self)
            lock()
            var confirmed = false
            for _ in 0..<50 {
                guard self.sessionID == id else { return }
                if Self.isScreenLocked() == true {
                    confirmed = true
                    break
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard confirmed else { throw LidError.unavailable }
            try self.refreshLease(locked: true)
            try await self.waitForStatus("active", id: id)
            guard self.sessionID == id else { return }
            guard Self.isScreenLocked() == true else { throw LidError.unavailable }
            self.isPreparing = false
            self.isRunning = true
            self.sleepDisplays()
            self.monitor = Task { [weak self] in
                var wasClosed = Self.lidIsClosed()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    guard let self, self.sessionID == id else { return }
                    // Unknown lock state fails closed: stop renewing the lease.
                    guard Self.isScreenLocked() == true else { self.stop()
                        return
                    }
                    guard self.readStatus() == "active:\(id.uuidString)" else {
                        self.fail()
                        return
                    }
                    guard !Self.shouldStopForPower() else {
                        self.stop()
                        self
                            .errorMessage =
                            String(
                                localized: "Protected lid mode stopped because the battery is low or the Mac is too warm."
                            )
                        return
                    }
                    do { try self.refreshLease(locked: true) } catch { self.fail()
                        return
                    }
                    let closed = Self.lidIsClosed()
                    guard closed != nil else { self.fail()
                        return
                    }
                    if closed == true, wasClosed != true {
                        self.sleepDisplays()
                    }
                    wasClosed = closed
                }
            }
        } catch {
            guard self.sessionID == id else { return }
            self.fail()
        }
    }

    func stop() {
        let wasEngaged = self.isEngaged
        let oldID = self.sessionID
        self.sessionID = nil
        self.monitor?.cancel()
        self.monitor = nil
        if
            let leaseURL, let oldID,
            let value = try? String(contentsOf: leaseURL, encoding: .utf8),
            value.hasSuffix(":" + oldID.uuidString)
        {
            try? FileManager.default.removeItem(at: leaseURL)
        }
        self.leaseURL = nil
        self.isRunning = false
        self.isPreparing = false
        // Keep the dynamically loaded lock function valid for the app lifetime.
        if wasEngaged {
            self.didStop?()
        }
    }

    private func fail() {
        self.stop()
        self
            .errorMessage =
            String(
                localized: "Protected lid mode could not be confirmed and has been stopped. Allow the administrator request, check that no other app disables lid sleep, and try again."
            )
    }

    private func refreshLease(locked: Bool) throws {
        guard let leaseURL, let sessionID else { throw LidError.unavailable }
        let value = "\(locked ? "locked" : "pending"):\(ProcessInfo.processInfo.processIdentifier):\(sessionID.uuidString)"
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

    private func sleepDisplays() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
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

    private static func lidIsClosed() -> Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        return IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
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
