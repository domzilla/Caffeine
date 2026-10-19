//
//  LidAudioMuter.swift
//  Caffeine
//

import CoreAudio
import Foundation
import IOKit

/// Mutes the built-in speakers while the lid is closed in lid-closed mode, so a closed Mac
/// stays as quiet as a sleeping one. Headphones, AirPods and external speakers are left
/// alone, and nothing is touched if the speakers were already muted.
@MainActor
final class LidAudioMuter {
    private var timer: Timer?
    /// The device we muted, so we only ever unmute what we muted ourselves.
    private var mutedDevice: AudioObjectID?

    func start() {
        guard self.timer == nil else { return }
        self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in self.update() }
        }
        self.timer?.tolerance = 0.3
        self.update()
    }

    func stop() {
        self.timer?.invalidate()
        self.timer = nil
        self.unmute()
    }

    // MARK: - Private

    private func update() {
        if Self.isLidClosed {
            self.muteIfNeeded()
        } else {
            self.unmute()
        }
    }

    private func muteIfNeeded() {
        guard
            self.mutedDevice == nil,
            let device = Self.defaultOutputDevice(),
            Self.isBuiltIn(device),
            Self.isMuted(device) == false,
            Self.setMuted(device, true) else
        {
            return
        }
        self.mutedDevice = device
    }

    private func unmute() {
        guard let device = mutedDevice else { return }
        Self.setMuted(device, false)
        self.mutedDevice = nil
    }

    // MARK: - System state

    private static var isLidClosed: Bool {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(rootDomain) }
        let value = IORegistryEntryCreateCFProperty(
            rootDomain,
            kAppleClamshellStateKey as CFString,
            kCFAllocatorDefault,
            0
        )
        return (value?.takeRetainedValue() as? Bool) ?? false
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func isBuiltIn(_ device: AudioObjectID) -> Bool {
        var transportType: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transportType)
        return status == noErr && transportType == kAudioDeviceTransportTypeBuiltIn
    }

    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private static func isMuted(_ device: AudioObjectID) -> Bool? {
        guard AudioObjectHasProperty(device, &self.muteAddress) else { return nil }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &self.muteAddress, 0, nil, &size, &muted) == noErr else {
            return nil
        }
        return muted != 0
    }

    @discardableResult
    private static func setMuted(_ device: AudioObjectID, _ muted: Bool) -> Bool {
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(device, &self.muteAddress, 0, nil, size, &value) == noErr
    }
}
