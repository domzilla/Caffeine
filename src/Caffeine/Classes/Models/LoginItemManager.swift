//
//  LoginItemManager.swift
//  Caffeine
//

import Combine
import DZFoundation
import Foundation
import ServiceManagement

@MainActor
final class LoginItemManager: ObservableObject {
    static let shared = LoginItemManager()

    @Published private(set) var startsAtLogin = false
    @Published private(set) var requiresApproval = false

    private init() {
        self.refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status

        self.startsAtLogin = status == .enabled || status == .requiresApproval
        self.requiresApproval = status == .requiresApproval
    }

    func setStartsAtLogin(_ startsAtLogin: Bool) {
        do {
            if startsAtLogin, !self.startsAtLogin {
                try SMAppService.mainApp.register()
            } else if !startsAtLogin, self.startsAtLogin {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            DZErrorLog(error)
        }

        self.refresh()
    }
}
