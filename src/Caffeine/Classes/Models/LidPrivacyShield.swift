import AppKit
import QuartzCore

/// Keeps desktop pixels covered before macOS can relight the internal panel.
/// This is an opaque visual cover, not a substitute for native authentication.
@MainActor
final class LidPrivacyShield {
    private var panel: PrivacyPanel?
    private var isVisible = false

    init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(self.screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    func prepare() {
        guard self.panel == nil else { self.updateFrame()
            return
        }
        guard let screen = self.builtInScreen else { return }
        let panel = PrivacyPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.panel = panel
    }

    func show() {
        self.prepare()
        self.isVisible = true
        self.panel?.orderFrontRegardless()
        self.panel?.displayIfNeeded()
        CATransaction.flush()
    }

    func hide() {
        self.isVisible = false
        self.panel?.orderOut(nil)
    }

    private var builtInScreen: NSScreen? {
        NSScreen.screens.first {
            guard let number = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        }
    }

    private func updateFrame() {
        // Keep the existing cover if the internal display disappears while shut.
        if let screen = self.builtInScreen {
            self.panel?.setFrame(screen.frame, display: true)
        }
    }

    @objc
    private func screensChanged() {
        self.updateFrame()
        if self.isVisible {
            self.show()
        }
    }
}

private final class PrivacyPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}
