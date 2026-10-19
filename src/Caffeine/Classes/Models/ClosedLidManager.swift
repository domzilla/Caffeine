//
//  ClosedLidManager.swift
//  Caffeine
//

import AppKit
import Combine
import Foundation
import IOKit.ps
import ServiceManagement

/// Keeps the Mac awake with the lid closed while Caffeine is active.
///
/// Lid-close sleep ignores power assertions, so this talks to `CaffeineHelper`, a privileged
/// launchd daemon registered through `SMAppService`, which toggles `pmset disablesleep`.
/// The helper restores the previous setting when this app releases it or its connection
/// drops, so a crash or force quit can't leave the Mac unable to sleep.
@MainActor
final class ClosedLidManager: ObservableObject {
    static let shared = ClosedLidManager()

    /// Lid-closed mode turns itself off on battery below this percentage.
    static let batteryCutoff = 10

    /// Registration state of the helper daemon.
    @Published private(set) var status: SMAppService.Status
    /// Whether the helper currently holds sleep disabled for us.
    @Published private(set) var isHolding = false {
        didSet {
            guard self.isHolding != oldValue else { return }
            self.isHolding ? self.audioMuter.start() : self.audioMuter.stop()
        }
    }
    /// Last error to show in preferences, if any.
    @Published private(set) var lastError: String?

    private let service = SMAppService.daemon(plistName: ClosedLidHelper.plistName)
    private var connection: NSXPCConnection?
    private var wantsHold = false
    private var batteryTimer: Timer?
    private var approvalTimer: Timer?
    private let audioMuter = LidAudioMuter()

    private init() {
        self.status = self.service.status

        // Waking the helper lets it undo a setting left behind if it ever crashed while holding.
        if self.status == .enabled {
            let connection = self.makeConnection()
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in }
            (proxy as? ClosedLidHelperProtocol)?.allowSleep {
                Task { @MainActor in
                    if !self.wantsHold, self.connection === connection {
                        connection.invalidate()
                        self.connection = nil
                    }
                }
            }
        }
    }

    // MARK: - Registration

    /// Registers the helper. The first time, macOS asks the user to approve it in
    /// System Settings › General › Login Items.
    func register() {
        self.lastError = nil
        do {
            try self.service.register()
        } catch {
            // `.requiresApproval` is reported as an error but isn't one.
            if self.service.status != .requiresApproval {
                self.lastError = error.localizedDescription
            }
        }
        self.refreshStatus()
        if self.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            self.watchForApproval()
        }
    }

    /// Polls while the user is in System Settings, so the switch takes effect as soon as it's approved.
    private func watchForApproval() {
        self.approvalTimer?.invalidate()
        let deadline = Date().addingTimeInterval(300)
        self.approvalTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
            Task { @MainActor in
                self.refreshStatus()
                if self.status != .requiresApproval || Date() > deadline {
                    timer.invalidate()
                }
            }
        }
    }

    func unregister() {
        self.release()
        self.service.unregister { _ in
            Task { @MainActor in self.refreshStatus() }
        }
    }

    func refreshStatus() {
        let wasEnabled = self.status == .enabled
        self.status = self.service.status
        // Pick up a hold that was waiting for the user to approve the helper.
        if self.wantsHold, !wasEnabled, self.status == .enabled, !self.isHolding {
            self.requestHold()
        }
    }

    // MARK: - Holding

    /// Asks the helper to keep the Mac awake with the lid closed.
    func hold() {
        self.wantsHold = true
        self.startBatteryMonitoring()
        self.refreshStatus()
        guard self.status == .enabled else { return }
        self.requestHold()
    }

    /// Lets lid-close sleep work normally again.
    func release() {
        self.wantsHold = false
        self.stopBatteryMonitoring()
        guard let connection else { return }
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in }
        (proxy as? ClosedLidHelperProtocol)?.allowSleep {
            Task { @MainActor in
                // Dropping the connection also releases, so close it once the helper replied.
                connection.invalidate()
            }
        }
        self.connection = nil
        self.isHolding = false
    }

    // MARK: - Private

    private func requestHold() {
        let connection = self.connection ?? self.makeConnection()
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            Task { @MainActor in
                self.lastError = error.localizedDescription
                self.isHolding = false
            }
        }
        (proxy as? ClosedLidHelperProtocol)?.preventSleep { success in
            Task { @MainActor in
                guard self.wantsHold else { return }
                self.isHolding = success
                if !success {
                    self.lastError = String(localized: "Caffeine couldn't turn off lid-close sleep.")
                }
            }
        }
    }

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(machServiceName: ClosedLidHelper.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: ClosedLidHelperProtocol.self)
        if let requirement = ClosedLidHelper.sameTeamRequirement() {
            connection.setCodeSigningRequirement(requirement)
        }
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in
                guard let self, self.connection === connection else { return }
                self.connection = nil
                self.isHolding = false
            }
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    private func startBatteryMonitoring() {
        guard self.batteryTimer == nil else { return }
        self.batteryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in self.checkBattery() }
        }
        self.checkBattery()
    }

    private func stopBatteryMonitoring() {
        self.batteryTimer?.invalidate()
        self.batteryTimer = nil
    }

    private func checkBattery() {
        guard let level = Self.batteryLevelOnBattery(), level < Self.batteryCutoff else { return }
        self.release()
        self.lastError = String(
            format: String(localized: "Lid-closed mode turned off at %d%% battery."),
            level
        )
    }

    /// Battery percentage, or `nil` when on power or there's no battery.
    private static func batteryLevelOnBattery() -> Int? {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else
        {
            return nil
        }
        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else
            {
                continue
            }
            return current * 100 / max
        }
        return nil
    }
}
