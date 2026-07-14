import AppKit
import Foundation
import KeyboardShortcuts
import Observation
import os

let defaultPushToTalkShortcut = KeyboardShortcuts.Shortcut(.space, modifiers: [.option])

extension KeyboardShortcuts.Name {
    static let pushToTalk = Self(
        "pushToTalk",
        default: defaultPushToTalkShortcut
    )
}

protocol HotkeyBindingService: AnyObject {
    func currentShortcut() -> KeyboardShortcuts.Shortcut?
    func setShortcut(_ shortcut: KeyboardShortcuts.Shortcut?)
    func events() -> AsyncStream<KeyboardShortcuts.EventType>
}

final class LiveHotkeyBindingService: HotkeyBindingService {
    func currentShortcut() -> KeyboardShortcuts.Shortcut? {
        KeyboardShortcuts.getShortcut(for: .pushToTalk)
    }

    func setShortcut(_ shortcut: KeyboardShortcuts.Shortcut?) {
        KeyboardShortcuts.setShortcut(shortcut, for: .pushToTalk)
    }

    func events() -> AsyncStream<KeyboardShortcuts.EventType> {
        KeyboardShortcuts.events(for: .pushToTalk)
    }
}

@MainActor
@Observable
final class CueHotkeyManager {
    private(set) var shortcut: KeyboardShortcuts.Shortcut?

    private let logger = Logger(subsystem: "dev.sonawalla.Cue", category: "Hotkey")
    private let eventTask: Task<Void, Never>

    private static let initializationFlagKey = "Cue.pushToTalkShortcutInitialized"

    init(
        appModel: CueAppModel,
        defaults: UserDefaults = .standard,
        bindingService: HotkeyBindingService? = nil
    ) {
        let bindingService = bindingService ?? LiveHotkeyBindingService()
        shortcut = nil

        let events = bindingService.events()
        eventTask = Task { @MainActor [weak appModel] in
            for await event in events {
                guard let appModel else {
                    return
                }

                switch event {
                case .keyDown:
                    appModel.handlePushToTalkPressed()
                case .keyUp:
                    appModel.handlePushToTalkReleased()
                @unknown default:
                    continue
                }
            }
        }

        initializeShortcutIfNeeded(defaults: defaults, bindingService: bindingService)
        shortcut = bindingService.currentShortcut()
    }

    deinit {
        eventTask.cancel()
    }

    var shortcutSummary: String {
        Self.describe(shortcut)
    }

    var hasConfiguredShortcut: Bool {
        shortcut != nil
    }

    func updateShortcutSummary(_ shortcut: KeyboardShortcuts.Shortcut?) {
        self.shortcut = shortcut
        logger.info("Push-to-talk shortcut updated to \(self.shortcutSummary, privacy: .public)")
    }

    private static func describe(_ shortcut: KeyboardShortcuts.Shortcut?) -> String {
        shortcut?.description ?? "Not configured"
    }

    private func initializeShortcutIfNeeded(
        defaults: UserDefaults,
        bindingService: HotkeyBindingService
    ) {
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
