//
//  MenuBarController.swift
//  Caffeine
//
//  Created by Dominic Rodemer on 11.11.25.
//

import Cocoa
import Combine
import QuartzCore
import Sparkle
import SwiftUI

@MainActor
class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var viewModel: CaffeineViewModel
    private var preferencesWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var coffeeFillTimer: Timer?
    private var coffeeFillAnimationStartTime: TimeInterval?
    private var coffeeFillInactiveImage: NSImage?
    private var coffeeFillActiveImage: NSImage?
    private var isAnimatingCoffeeFill = false
    private let updaterController: SPUStandardUpdaterController
    private let coffeeFillAnimationDuration: TimeInterval = 0.42

    init(updaterController: SPUStandardUpdaterController) {
        self.updaterController = updaterController
        self.viewModel = CaffeineViewModel()
        super.init()
        self.setupMenuBar()
        self.setupObservers()

        // Ensure icon reflects the current state after full initialization
        // This is important because ViewModel.init() might activate if "activate at launch" is enabled
        self.updateIcon()
    }

    func cleanup() {
        self.cancelCoffeeFillAnimation()
        self.viewModel.deactivate()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    private func setupMenuBar() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }

        // Set up button actions (icon will be set after observers are configured)
        button.action = #selector(self.statusItemClicked(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupObservers() {
        self.viewModel.$isActive
            .sink { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.updateIcon()
                }
            }
            .store(in: &self.cancellables)

        self.viewModel.$showPreferences
            .sink { [weak self] show in
                if show {
                    self?.showPreferencesWindow()
                }
            }
            .store(in: &self.cancellables)
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }

        if self.isAnimatingCoffeeFill, self.viewModel.isActive {
            return
        }

        self.cancelCoffeeFillAnimation()

        let imageName = self.viewModel.isActive ? "active" : "inactive"
        if let image = NSImage(named: NSImage.Name(imageName)) {
            button.image = image
        }
    }

    @objc
    private func statusItemClicked(_ button: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp || (event.type == .leftMouseUp && event.modifierFlags.contains(.control)) {
            self.showContextMenu()
        } else {
            let shouldAnimateCoffeeFill = !self.viewModel.isActive && self.isCoffeeAnimationEnabled
            if shouldAnimateCoffeeFill {
                self.startCoffeeFillAnimation(on: button)
            } else {
                self.cancelCoffeeFillAnimation()
            }

            self.viewModel.toggleActive()
        }
    }

    private func startCoffeeFillAnimation(on button: NSStatusBarButton) {
        guard
            let inactiveImage = NSImage(named: NSImage.Name("inactive")),
            let activeImage = NSImage(named: NSImage.Name("active"))
        else {
            return
        }

        self.coffeeFillTimer?.invalidate()
        self.coffeeFillInactiveImage = inactiveImage
        self.coffeeFillActiveImage = activeImage
        self.isAnimatingCoffeeFill = true
        self.coffeeFillAnimationStartTime = CACurrentMediaTime()
        button.image = self.coffeeImage(inactiveImage: inactiveImage, activeImage: activeImage, fillProgress: 0)

        self.coffeeFillTimer = Timer.scheduledTimer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(self.updateCoffeeFillAnimationFrame(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    @objc
    private func updateCoffeeFillAnimationFrame(_ timer: Timer) {
        guard
            let button = statusItem?.button,
            let inactiveImage = coffeeFillInactiveImage,
            let activeImage = coffeeFillActiveImage,
            let startTime = coffeeFillAnimationStartTime
        else {
            self.cancelCoffeeFillAnimation()
            return
        }

        let elapsed = CACurrentMediaTime() - startTime
        let rawProgress = min(1.0, elapsed / self.coffeeFillAnimationDuration)
        let fillProgress = self.easeOutQuint(rawProgress)
        button.image = self.coffeeImage(inactiveImage: inactiveImage, activeImage: activeImage, fillProgress: fillProgress)

        if rawProgress >= 1.0 {
            timer.invalidate()
            self.coffeeFillTimer = nil
            self.coffeeFillAnimationStartTime = nil
            self.coffeeFillInactiveImage = nil
            self.coffeeFillActiveImage = nil
            self.isAnimatingCoffeeFill = false
            self.updateIcon()
        }
    }

    private func cancelCoffeeFillAnimation() {
        self.coffeeFillTimer?.invalidate()
        self.coffeeFillTimer = nil
        self.coffeeFillAnimationStartTime = nil
        self.coffeeFillInactiveImage = nil
        self.coffeeFillActiveImage = nil
        self.isAnimatingCoffeeFill = false
    }

    private func coffeeImage(inactiveImage: NSImage, activeImage: NSImage, fillProgress: Double) -> NSImage {
        let imageSize = inactiveImage.size
        let image = NSImage(size: imageSize)
        let fillHeight = imageSize.height * fillProgress

        image.lockFocus()
        inactiveImage.draw(in: NSRect(origin: .zero, size: imageSize))

        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: imageSize.width, height: fillHeight)).addClip()
        activeImage.draw(in: NSRect(origin: .zero, size: imageSize))
        NSGraphicsContext.current?.restoreGraphicsState()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func easeOutQuint(_ progress: Double) -> Double {
        1.0 - pow(1.0 - progress, 5.0)
    }

    private var isCoffeeAnimationEnabled: Bool {
        let userPreference = UserDefaults.standard.object(forKey: PreferenceKeys.animateCoffeeIcon) as? Bool ?? true
        return userPreference && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func showContextMenu() {
        let menu = NSMenu()

        // Status info (only show if active)
        if self.viewModel.isActive, let timeString = viewModel.formattedTimeRemaining() {
            let infoItem = NSMenuItem(title: timeString, action: nil, keyEquivalent: "")
            infoItem.isEnabled = false
            menu.addItem(infoItem)
            menu.addItem(NSMenuItem.separator())
        }

        // Duration options in submenu
        let activateForItem = NSMenuItem(
            title: String(localized: "Activate for"),
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu()

        var durations: [(String, Int)] = [
            (String(localized: "Indefinitely"), 0),
            (String(localized: "5 minutes"), 5),
            (String(localized: "10 minutes"), 10),
            (String(localized: "15 minutes"), 15),
            (String(localized: "30 minutes"), 30),
            (String(localized: "1 hour"), 60),
            (String(localized: "2 hours"), 120),
            (String(localized: "5 hours"), 300),
        ]

        #if DEBUG
        durations.insert((String(localized: "1 minute"), 1), at: 1)
        #endif

        for (title, minutes) in durations {
            let item = NSMenuItem(
                title: title,
                action: #selector(activateWithDuration(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = minutes
            submenu.addItem(item)
        }

        activateForItem.submenu = submenu
        menu.addItem(activateForItem)

        menu.addItem(NSMenuItem.separator())

        // Preferences
        let prefsItem = NSMenuItem(
            title: String(localized: "Preferences..."),
            action: #selector(showPreferences(_:)),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)

        // About
        let aboutItem = NSMenuItem(
            title: String(localized: "About Caffeine"),
            action: #selector(showAbout(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        // Update
        let updatesItem = NSMenuItem(
            title: String(localized: "Check for Updates..."),
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updatesItem.target = self
        menu.addItem(updatesItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: String(localized: "Quit"),
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusItem?.menu = menu
        self.statusItem?.button?.performClick(nil)
        self.statusItem?.menu = nil
    }

    @objc
    private func activateWithDuration(_ sender: NSMenuItem) {
        let minutes = sender.tag
        let seconds = minutes > 0 ? TimeInterval(minutes * 60) : 0
        self.viewModel.activate(withTimeout: seconds)
    }

    @objc
    private func showPreferences(_: Any?) {
        self.showPreferencesWindow()
    }

    @objc
    private func checkForUpdates(_ sender: Any?) {
        self.updaterController.checkForUpdates(sender)
    }

    private func showPreferencesWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if self.preferencesWindow == nil {
            let contentView = PreferencesView(viewModel: viewModel)
            let hostingController = NSHostingController(rootView: contentView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = String(localized: "Welcome to Caffeine")
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 640, height: 420))
            window.center()

            self.preferencesWindow = window
        }

        self.preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    @objc
    private func showAbout(_: Any?) {
        NSApp.activate(ignoringOtherApps: true)

        let credits =
            String(
                localized: "© 2006 Tomas Franzén\n© 2018 Michael Jones\n© 2022 Dominic Rodemer\n\nSource code:\nhttps://github.caffeine-app.net"
            )

        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: credits),
        ])
    }

    @objc
    private func quit(_: Any?) {
        NSApp.terminate(nil)
    }
}
