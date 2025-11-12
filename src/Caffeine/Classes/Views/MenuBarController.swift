//
//  MenuBarController.swift
//  Caffeine
//
//  Created by Dominic Rodemer on 11.11.25.
//

import SwiftUI
import Cocoa
import Combine
import Sparkle

@MainActor
class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var viewModel: CaffeineViewModel
    private var preferencesWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private let updaterController: SPUStandardUpdaterController
    
    init(updaterController: SPUStandardUpdaterController) {
        self.updaterController = updaterController
        self.viewModel = CaffeineViewModel()
        super.init()
        setupMenuBar()
        setupObservers()
        
        // Ensure icon reflects the current state after full initialization
        // This is important because ViewModel.init() might activate if "activate at launch" is enabled
        updateIcon()
    }
    
    func cleanup() {
        viewModel.deactivate()
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem?.button else { return }
        
        // Set up button actions (icon will be set after observers are configured)
        button.action = #selector(statusItemClicked(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
    
    private func setupObservers() {
        viewModel.$isActive
            .sink { [weak self] _ in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.updateIcon()
                }
            }
            .store(in: &cancellables)
        
        viewModel.$showPreferences
            .sink { [weak self] show in
                if show {
                    self?.showPreferencesWindow()
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateIcon() {
        guard let button = statusItem?.button else { return }

        let imageName = viewModel.isActive ? "active" : "inactive"
        if let image = NSImage(named: NSImage.Name(imageName)) {
            image.isTemplate = false
            button.image = image
        }
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp || (event.type == .leftMouseUp && event.modifierFlags.contains(.control)) {
            showContextMenu()
        } else {
            viewModel.toggleActive()
        }
    }
    
    private func showContextMenu() {
        let menu = NSMenu()
        
        // Status info (only show if active)
        if viewModel.isActive, let timeString = viewModel.formattedTimeRemaining() {
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
            (String(localized: "5 hours"), 300)
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
        
        //Update
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
        
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }
    
    @objc private func activateWithDuration(_ sender: NSMenuItem) {
        let minutes = sender.tag
        let seconds = minutes > 0 ? TimeInterval(minutes * 60) : 0
        viewModel.activate(withTimeout: seconds)
    }
    
    @objc private func showPreferences(_ sender: Any?) {
        showPreferencesWindow()
    }
    
    @objc private func checkForUpdates(_ sender: Any?) {
        updaterController.checkForUpdates(sender)
    }
    
    private func showPreferencesWindow() {
        NSApp.activate(ignoringOtherApps: true)
        
        if preferencesWindow == nil {
            let contentView = PreferencesView(viewModel: viewModel)
            let hostingController = NSHostingController(rootView: contentView)
            
            let window = NSWindow(contentViewController: hostingController)
            window.title = String(localized: "Welcome to Caffeine")
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 640, height: 420))
            window.center()
            
            preferencesWindow = window
        }
        
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }
    
    @objc private func showAbout(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        
        let credits = String(localized: "© 2006 Tomas Franzén\n© 2018 Michael Jones\n© 2022 Dominic Rodemer\n\nSource code:\nhttps://github.caffeine-app.net")
        
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: credits)
        ])
    }
    
    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}
