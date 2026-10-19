//
//  main.swift
//  CaffeineHelper
//
//  Privileged launchd daemon, registered by the app through SMAppService. It toggles
//  `pmset disablesleep` on behalf of Caffeine so the Mac stays awake with the lid closed.
//

import Foundation
import IOKit
import os

private let log = Logger(subsystem: "net.domzilla.caffeine.helper", category: "sleep")

/// Owns the system sleep setting while at least one client holds it.
final class SleepController {
    static let shared = SleepController()

    private let queue = DispatchQueue(label: "net.domzilla.caffeine.helper.sleep")
    private var holders = Set<ObjectIdentifier>()
    private var previousValue: Bool?

    /// Written while sleep is disabled so a crashed helper can restore it on its next launch.
    private let markerURL: URL = {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("PreviousSleepDisabled")
    }()

    private init() {
        self.restoreAfterCrash()
    }

    func hold(_ connection: NSXPCConnection) -> Bool {
        self.queue.sync {
            if self.holders.isEmpty {
                let previous = Self.isSleepDisabled()
                // Record what to restore before changing anything, in case we crash midway.
                try? (previous ? "1" : "0").write(to: self.markerURL, atomically: true, encoding: .utf8)
                guard Self.setSleepDisabled(true) else {
                    log.error("Couldn't disable sleep")
                    Self.setSleepDisabled(previous)
                    try? FileManager.default.removeItem(at: self.markerURL)
                    return false
                }
                self.previousValue = previous
                log.info("Sleep disabled (previously \(previous ? "disabled" : "enabled", privacy: .public))")
            }
            self.holders.insert(ObjectIdentifier(connection))
            return true
        }
    }

    func release(_ connection: NSXPCConnection) {
        self.queue.sync {
            guard self.holders.remove(ObjectIdentifier(connection)) != nil, self.holders.isEmpty else { return }
            self.restore()
        }
    }

    func releaseAll() {
        self.queue.sync {
            guard !self.holders.isEmpty else { return }
            self.holders.removeAll()
            self.restore()
        }
    }

    var isIdle: Bool {
        self.queue.sync { self.holders.isEmpty }
    }

    // MARK: - Private

    private func restore() {
        let ok = Self.setSleepDisabled(self.previousValue ?? false)
        log.info("Sleep setting restored: \(ok ? "ok" : "failed", privacy: .public)")
        self.previousValue = nil
        try? FileManager.default.removeItem(at: self.markerURL)
    }

    private func restoreAfterCrash() {
        guard let value = try? String(contentsOf: markerURL, encoding: .utf8) else { return }
        log.info("Restoring sleep setting left behind by a previous run")
        Self.setSleepDisabled(value.hasPrefix("1"))
        try? FileManager.default.removeItem(at: self.markerURL)
    }

    /// Reads the setting from the kernel's power domain. `pmset -g` can't be used here: run
    /// from inside the sandbox it can't see the system preferences that hold this setting.
    private static func isSleepDisabled() -> Bool {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(rootDomain) }
        let value = IORegistryEntryCreateCFProperty(rootDomain, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)
        return (value?.takeRetainedValue() as? Bool) ?? false
    }

    /// pmset exits with 0 even when it refuses a change, so read the setting back. The new
    /// value takes a moment to reach the kernel, so give it a few seconds.
    @discardableResult
    private static func setSleepDisabled(_ disabled: Bool) -> Bool {
        self.pmset(["-a", "disablesleep", disabled ? "1" : "0"])
        for _ in 0..<50 {
            if self.isSleepDisabled() == disabled {
                return true
            }
            usleep(100_000)
        }
        return false
    }

    private static func pmset(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, "")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

/// Handles one connection from the app.
final class HelperService: NSObject, ClosedLidHelperProtocol {
    private weak var connection: NSXPCConnection?

    init(connection: NSXPCConnection) {
        self.connection = connection
    }

    func preventSleep(withReply reply: @escaping (Bool) -> Void) {
        guard let connection else { return reply(false) }
        reply(SleepController.shared.hold(connection))
    }

    func allowSleep(withReply reply: @escaping () -> Void) {
        if let connection {
            SleepController.shared.release(connection)
        }
        reply()
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private var connectionCount = 0
    private let lock = NSLock()

    func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Only accept the app it ships with: same team, verified by the system on every message.
        guard let requirement = ClosedLidHelper.sameTeamRequirement() else { return false }
        connection.setCodeSigningRequirement(requirement)

        connection.exportedInterface = NSXPCInterface(with: ClosedLidHelperProtocol.self)
        connection.exportedObject = HelperService(connection: connection)

        // Quit, crash or force quit of the app invalidates the connection and restores sleep.
        connection.invalidationHandler = { [weak self, unowned connection] in
            SleepController.shared.release(connection)
            self?.connectionClosed()
        }

        self.lock.withLock { self.connectionCount += 1 }
        connection.resume()
        return true
    }

    private func connectionClosed() {
        let remaining = self.lock.withLock {
            self.connectionCount -= 1
            return self.connectionCount
        }
        // launchd relaunches the helper on demand, so don't linger once nobody needs it.
        if remaining == 0, SleepController.shared.isIdle {
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if self.lock.withLock({ self.connectionCount }) == 0 {
                    exit(0)
                }
            }
        }
    }
}

// Restore sleep when launchd stops the helper (unregister, logout, shutdown).
signal(SIGTERM, SIG_IGN)
let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termSource.setEventHandler {
    SleepController.shared.releaseAll()
    exit(0)
}
termSource.resume()

_ = SleepController.shared

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: ClosedLidHelper.machServiceName)
listener.delegate = delegate
listener.resume()

dispatchMain()
