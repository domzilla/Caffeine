import Foundation
import IOKit.ps

extension PowerSnapshot {
    static func current() -> PowerSnapshot {
        var snapshot = PowerSnapshot(
            onExternalPower: nil, batteryFraction: nil,
            isTooHot: [.serious, .critical].contains(ProcessInfo.processInfo.thermalState)
        )
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return snapshot }
        if let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() {
            snapshot.onExternalPower = source as String == kIOPSACPowerValue
        }
        guard let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return snapshot }
        for source in sources {
            guard
                let values = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                values[kIOPSTransportTypeKey] as? String == kIOPSInternalType,
                let current = values[kIOPSCurrentCapacityKey] as? Int,
                let maximum = values[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            snapshot.batteryFraction = Double(current) / Double(maximum)
            break
        }
        return snapshot
    }
}
