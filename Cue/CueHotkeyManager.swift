import AppKit
import Foundation
import KeyboardShortcuts
import Observation
import os

let defaultPushToTalkShortcut = KeyboardShortcuts.Shortcut(.d, modifiers: [.control, .option])

extension KeyboardShortcuts.Name {
    static let pushToTalk = Self(
        "pushToTalk",
        default: defaultPushToTalkShortcut
    )
}

protocol HotkeyBindingService: AnyObject {
    func currentShortcut() -> KeyboardShortcuts.Shortcut?
    func setShortcut(_ shortcut: KeyboardShortcuts.Shortcut?)
    func registerKeyDown(_ action: @escaping () -> Void)
    func registerKeyUp(_ action: @escaping () -> Void)
}

final class LiveHotkeyBindingService: HotkeyBindingService {
    func currentShortcut() -> KeyboardShortcuts.Shortcut? {
        KeyboardShortcuts.getShortcut(for: .pushToTalk)
    }

    func setShortcut(_ shortcut: KeyboardShortcuts.Shortcut?) {
        KeyboardShortcuts.setShortcut(shortcut, for: .pushToTalk)
    }

    func registerKeyDown(_ action: @escaping () -> Void) {
        KeyboardShortcuts.onKeyDown(for: .pushToTalk, action: action)
    }

    func registerKeyUp(_ action: @escaping () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .pushToTalk, action: action)
    }
}

final class DisabledHotkeyBindingService: HotkeyBindingService {
    private var shortcut: KeyboardShortcuts.Shortcut?

    init(shortcut: KeyboardShortcuts.Shortcut? = defaultPushToTalkShortcut) {
        self.shortcut = shortcut
    }

    func currentShortcut() -> KeyboardShortcuts.Shortcut? {
        shortcut
    }

    func setShortcut(_ shortcut: KeyboardShortcuts.Shortcut?) {
        self.shortcut = shortcut
    }

    func registerKeyDown(_ action: @escaping () -> Void) {
        _ = action
    }

    func registerKeyUp(_ action: @escaping () -> Void) {
        _ = action
    }
}

@MainActor
@Observable
final class CueHotkeyManager {
    var shortcutSummary: String
    var hasConfiguredShortcut: Bool

    private weak var appModel: CueAppModel?
    private let defaults: UserDefaults
    private let bindingService: HotkeyBindingService
    private let logger = Logger(subsystem: "dev.sonawalla.Cue", category: "Hotkey")

    private static let initializationFlagKey = "Cue.pushToTalkShortcutInitialized"

    init(
        appModel: CueAppModel,
        defaults: UserDefaults = .standard,
        bindingService: HotkeyBindingService? = nil
    ) {
        self.appModel = appModel
        self.defaults = defaults
        self.bindingService = bindingService ?? LiveHotkeyBindingService()
        shortcutSummary = "Not configured"
        hasConfiguredShortcut = false

        initializeShortcutIfNeeded()

        let currentShortcut = self.bindingService.currentShortcut()
        shortcutSummary = Self.describe(currentShortcut)
        hasConfiguredShortcut = currentShortcut != nil

        self.bindingService.registerKeyDown { [weak self] in
            guard let self, let appModel = self.appModel else {
                return
            }

            Task {
                await appModel.handlePushToTalkPressed()
            }
        }

        self.bindingService.registerKeyUp { [weak self] in
            guard let self, let appModel = self.appModel else {
                return
            }

            Task {
                await appModel.handlePushToTalkReleased()
            }
        }
    }

    func updateShortcutSummary(_ shortcut: KeyboardShortcuts.Shortcut?) {
        shortcutSummary = Self.describe(shortcut)
        hasConfiguredShortcut = shortcut != nil
        logger.info("Push-to-talk shortcut updated to \(self.shortcutSummary, privacy: .public)")
    }

    private static func describe(_ shortcut: KeyboardShortcuts.Shortcut?) -> String {
        shortcut?.description ?? "Not configured"
    }

    private func initializeShortcutIfNeeded() {
        guard !defaults.bool(forKey: Self.initializationFlagKey) else {
            return
        }

        defer {
            defaults.set(true, forKey: Self.initializationFlagKey)
        }

        guard bindingService.currentShortcut() == nil else {
            return
        }

        bindingService.setShortcut(defaultPushToTalkShortcut)
        logger.info("Initialized push-to-talk shortcut to the supported default")
    }

}
