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
                permissionService: UITestPermissionService(),
                soundService: UITestSoundService()
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
            pasteDuration: 0.05,
            clipboardRestoreState: .restored,
            pasteCommandPostedAt: Date()
        )
    }
}

@MainActor
protocol PlayableSound: AnyObject {
    @discardableResult
    func play() -> Bool

    @discardableResult
    func stop() -> Bool
}

extension NSSound: PlayableSound {}

@MainActor
final class SystemSoundService: SoundService {
    private let recordingStartedSound: any PlayableSound
    private let recordingStoppedSound: any PlayableSound
    private let errorSound: any PlayableSound

    init(
        recordingStartedSound: (any PlayableSound)? = nil,
        recordingStoppedSound: (any PlayableSound)? = nil,
        errorSound: (any PlayableSound)? = nil
    ) {
        self.recordingStartedSound = recordingStartedSound
            ?? Self.makeSound(named: NSSound.Name("Funk"))
            ?? SilentPlayableSound()
        self.recordingStoppedSound = recordingStoppedSound
            ?? Self.makeSound(named: NSSound.Name("Bottle"))
            ?? SilentPlayableSound()
        self.errorSound = errorSound
            ?? Self.makeSound(named: NSSound.Name("Basso"))
            ?? SilentPlayableSound()
    }

    func playRecordingStarted() {
        restart(recordingStartedSound)
    }

    func playRecordingStopped() {
        restart(recordingStoppedSound)
    }

    func playError() {
        restart(errorSound)
    }

    private func restart(_ sound: any PlayableSound) {
        sound.stop()
        _ = sound.play()
    }

    private static func makeSound(named name: NSSound.Name) -> NSSound? {
        guard let template = NSSound(named: name) else {
            return nil
        }

        return template.copy() as? NSSound
    }
}

@MainActor
private final class UITestSoundService: SoundService {
    func playRecordingStarted() {}
    func playRecordingStopped() {}
    func playError() {}
}

@MainActor
private final class SilentPlayableSound: PlayableSound {
    @discardableResult
    func play() -> Bool {
        false
    }

    @discardableResult
    func stop() -> Bool {
        false
    }
}
