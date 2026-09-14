import Foundation
import IOKit
import IOKit.pwr_mgt

@MainActor
final class LidMonitor {
    private let changed: (Bool) -> Void
    private var port: IONotificationPortRef?
    private var notification: io_object_t = 0

    init(changed: @escaping (Bool) -> Void) {
        self.changed = changed
    }

    func start() -> Bool {
        self.stop()
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return false }
        self.port = port
        IONotificationPortSetDispatchQueue(port, .main)
        let result = IOServiceAddInterestNotification(
            port, root, kIOGeneralInterest,
            { context, _, message, argument in
                // IOPM.h macro is not imported by Swift: sys_iokit | err_sub(13) | 0x100.
                let clamshellMessage: UInt32 = (0x38 << 26) | (13 << 14) | 0x100
                guard message == clamshellMessage, let context else { return }
                let closed = (UInt(bitPattern: argument) & 1) != 0
                MainActor.assumeIsolated {
                    let monitor = Unmanaged<LidMonitor>.fromOpaque(context).takeUnretainedValue()
                    monitor.changed(closed)
                }
            },
            Unmanaged.passUnretained(self).toOpaque(), &self.notification
        )
        if result != kIOReturnSuccess {
            self.stop()
            return false
        }
        return true
    }

    func stop() {
        if self.notification != 0 {
            IOObjectRelease(self.notification)
            self.notification = 0
        }
        if let port {
            IONotificationPortDestroy(port)
            self.port = nil
        }
    }

    static func readClosed() -> Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        return IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
    }
}
