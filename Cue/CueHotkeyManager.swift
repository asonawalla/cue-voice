import AppKit
import KeyboardShortcuts
import Observation
import os

private let defaultPushToTalkShortcut = KeyboardShortcuts.Shortcut(.d, modifiers: [.control, .option])
private let unsupportedFunctionShortcut = KeyboardShortcuts.Shortcut(.function)

extension KeyboardShortcuts.Name {
    static let pushToTalk = Self(
        "pushToTalk",
        default: defaultPushToTalkShortcut
    )
}

@MainActor
@Observable
final class CueHotkeyManager {
    var shortcutSummary: String
    var hasConfiguredShortcut: Bool

    private weak var appModel: CueAppModel?
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "dev.sonawalla.Cue", category: "Hotkey")

    private static let initializationFlagKey = "Cue.pushToTalkShortcutInitialized"
    private static let unsupportedShortcutMigrationFlagKey = "Cue.pushToTalkShortcutMigratedFromUnsupportedFunctionKey"

    init(
        appModel: CueAppModel,
        defaults: UserDefaults = .standard
    ) {
        self.appModel = appModel
        self.defaults = defaults
        shortcutSummary = "Not configured"
        hasConfiguredShortcut = false

        migrateUnsupportedFunctionShortcutIfNeeded()
        initializeShortcutIfNeeded()

        let currentShortcut = KeyboardShortcuts.getShortcut(for: .pushToTalk)
        shortcutSummary = Self.describe(currentShortcut)
        hasConfiguredShortcut = currentShortcut != nil

        KeyboardShortcuts.onKeyDown(for: .pushToTalk) { [weak self] in
            guard let self, let appModel = self.appModel else {
                return
            }

            Task {
                await appModel.handlePushToTalkPressed()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .pushToTalk) { [weak self] in
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

        guard KeyboardShortcuts.getShortcut(for: .pushToTalk) == nil else {
            return
        }

        KeyboardShortcuts.setShortcut(defaultPushToTalkShortcut, for: .pushToTalk)
        logger.info("Initialized push-to-talk shortcut to the supported default")
    }

    private func migrateUnsupportedFunctionShortcutIfNeeded() {
        guard !defaults.bool(forKey: Self.unsupportedShortcutMigrationFlagKey) else {
            return
        }

        defer {
            defaults.set(true, forKey: Self.unsupportedShortcutMigrationFlagKey)
        }

        guard KeyboardShortcuts.getShortcut(for: .pushToTalk) == unsupportedFunctionShortcut else {
            return
        }

        KeyboardShortcuts.setShortcut(defaultPushToTalkShortcut, for: .pushToTalk)
        logger.info("Migrated push-to-talk shortcut from unsupported fn to the supported default")
    }
}
