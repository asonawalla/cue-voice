import AppKit
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
    func events() -> AsyncStream<KeyboardShortcuts.EventType>
}

final class LiveHotkeyBindingService: HotkeyBindingService {
    func currentShortcut() -> KeyboardShortcuts.Shortcut? {
        KeyboardShortcuts.getShortcut(for: .pushToTalk)
    }

    func events() -> AsyncStream<KeyboardShortcuts.EventType> {
        KeyboardShortcuts.events(for: .pushToTalk)
    }
}

@MainActor
@Observable
final class CueHotkeyManager {
    private(set) var shortcut: KeyboardShortcuts.Shortcut?

    private let logger = Logger(subsystem: CueAppConfiguration.bundleIdentifier, category: "Hotkey")
    private let eventTask: Task<Void, Never>

    init(
        appModel: CueAppModel,
        bindingService: HotkeyBindingService
    ) {
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
}
