#if DEBUG

import AppKit
import Foundation
import KeyboardShortcuts

@MainActor
extension CueAppEnvironment {
    static func makeUITesting() -> CueAppEnvironment {
        NSApplication.shared.setActivationPolicy(.regular)

        let model = CueAppModel(
            transcriptionService: UITestTranscriptionService(),
            insertionService: UITestTextInsertionService(),
            permissionService: UITestPermissionService(),
            soundService: UITestSoundService()
        )
        let hotkeyManager = CueHotkeyManager(
            appModel: model,
            bindingService: UITestHotkeyBindingService()
        )

        return CueAppEnvironment(model: model, hotkeyManager: hotkeyManager)
    }
}

private final class UITestHotkeyBindingService: HotkeyBindingService {
    func currentShortcut() -> KeyboardShortcuts.Shortcut? {
        defaultPushToTalkShortcut
    }

    func setShortcut(_ shortcut: KeyboardShortcuts.Shortcut?) {
        _ = shortcut
    }

    func events() -> AsyncStream<KeyboardShortcuts.EventType> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

@MainActor
private final class UITestPermissionService: PermissionService {
    func currentPermissionSnapshot() -> CuePermissionSnapshot {
        CuePermissionSnapshot(microphone: .granted, accessibility: .granted)
    }

    func requestMicrophonePermission() async {}

    func requestAccessibilityPermission() {}

    func openSystemSettings(for permission: CuePermissionKind) {
        _ = permission
    }
}

@MainActor
private final class UITestTranscriptionService: TranscriptionService {
    var statusHandler: TranscriptionStatusHandler?

    func prepareModel() async throws {
        await statusHandler?(.ready)
    }

    func startRecording() async throws {}

    func stopRecording() async throws -> String {
        "UI test transcript"
    }
}

@MainActor
private final class UITestTextInsertionService: TextInsertionService {
    func insert(_ text: String) async throws -> CueInsertionResult {
        CueInsertionResult(
            pasteDuration: 0.05,
            pasteCommandPostedAt: Date()
        )
    }
}

@MainActor
private final class UITestSoundService: SoundService {
    func playRecordingStarted() {}
    func playRecordingStopped() {}
    func playError() {}
}

#endif
