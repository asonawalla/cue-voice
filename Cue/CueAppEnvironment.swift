import AppKit
import Foundation

struct CueAppEnvironment {
    let model: CueAppModel
    let hotkeyManager: CueHotkeyManager

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(CueAppConfiguration.uiTestingLaunchArgument)
    }

    @MainActor
    static func make() -> CueAppEnvironment {
        if isUITesting {
            NSApplication.shared.setActivationPolicy(.regular)

            let model = CueAppModel(
                transcriptionService: UITestTranscriptionService(),
                insertionService: UITestTextInsertionService(),
                permissionService: UITestPermissionService()
            )
            let hotkeyManager = CueHotkeyManager(
                appModel: model,
                bindingService: DisabledHotkeyBindingService()
            )

            return CueAppEnvironment(model: model, hotkeyManager: hotkeyManager)
        }

        let model = CueAppModel()
        let hotkeyManager = CueHotkeyManager(appModel: model)
        return CueAppEnvironment(model: model, hotkeyManager: hotkeyManager)
    }
}

@MainActor
private final class UITestPermissionService: PermissionService {
    private var snapshot = CuePermissionSnapshot(microphone: .granted, accessibility: .granted)

    func currentPermissionSnapshot() -> CuePermissionSnapshot {
        snapshot
    }

    func requestMicrophonePermission() async -> CuePermissionState {
        snapshot = CuePermissionSnapshot(microphone: .granted, accessibility: snapshot.accessibility)
        return .granted
    }

    func requestAccessibilityPermission() {
        snapshot = CuePermissionSnapshot(microphone: snapshot.microphone, accessibility: .granted)
    }

    func openSystemSettings(for permission: CuePermissionKind) {
        _ = permission
    }

    func restartApplication() {}
}

@MainActor
private final class UITestTranscriptionService: TranscriptionService {
    var statusHandler: ((ModelPreparationStatus) -> Void)?

    func prepareModel() async throws {
        statusHandler?(.ready)
    }

    func startRecording() async throws {}

    func stopRecording() async throws -> CueTranscriptionResult {
        CueTranscriptionResult(
            text: "UI test transcript",
            language: "en",
            recordingDuration: 1.2,
            modelLoadDuration: 0.1,
            pipelineDuration: 0.2
        )
    }
}

@MainActor
private final class UITestTextInsertionService: TextInsertionService {
    func insert(_ text: String) async throws -> CueInsertionResult {
        CueInsertionResult(
            delivery: .pasteCommandSent,
            targetAppName: "Notes",
            targetBundleIdentifier: "com.apple.Notes",
            pasteDuration: 0.05
        )
    }
}

struct SystemSoundService: SoundService {
    func playRecordingStarted() {
        NSSound(named: NSSound.Name("Funk"))?.play()
    }

    func playRecordingStopped() {
        NSSound(named: NSSound.Name("Bottle"))?.play()
    }
}

@MainActor
private final class UITestSoundService: SoundService {
    func playRecordingStarted() {}
    func playRecordingStopped() {}
}
