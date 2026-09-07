import Foundation
import IOKit.ps

/// Power-source notifications wake an otherwise idle app when AC changes.
/// The periodic check remains a fallback and also observes thermal changes.
@MainActor
final class PowerSourceMonitor {
    private let changed: () -> Void
    private var source: CFRunLoopSource?

    init(changed: @escaping () -> Void) {
        self.changed = changed
    }

    func start() {
        guard self.source == nil else { return }
        self.source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue().changed()
            }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let source = self.source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    func stop() {
        if let source = self.source {
            CFRunLoopSourceInvalidate(source)
            self.source = nil
        }
    }

    deinit {
        if let source = self.source {
            CFRunLoopSourceInvalidate(source)
        }
    }
}
