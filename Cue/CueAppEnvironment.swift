import AppKit
import Foundation

struct CueAppEnvironment {
    let model: CueAppModel
    let hotkeyManager: CueHotkeyManager

    @MainActor
    static func make() -> CueAppEnvironment {
        let defaults = UserDefaults.standard
        let modelDirectory = CueAppConfiguration.modelDownloadDirectory()
        let debugCaptureDirectory = CueAppConfiguration.debugCaptureRootDirectory()
        let transcriptionService = WhisperKitTranscriptionService.live(
            defaults: defaults,
            modelDirectory: modelDirectory,
            debugCaptureDirectory: debugCaptureDirectory
        )
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: PasteboardInsertionService.live(),
            permissionService: SystemPermissionService(),
            soundService: SystemSoundService(),
            defaults: defaults,
            notificationCenter: .default,
            debugCaptureDirectory: debugCaptureDirectory
        )
        let hotkeyManager = CueHotkeyManager(
            appModel: model,
            bindingService: LiveHotkeyBindingService()
        )
        return CueAppEnvironment(model: model, hotkeyManager: hotkeyManager)
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
    private let recordingStartedSound: (any PlayableSound)?
    private let recordingStoppedSound: (any PlayableSound)?
    private let errorSound: (any PlayableSound)?

    init(
        recordingStartedSound: (any PlayableSound)? = nil,
        recordingStoppedSound: (any PlayableSound)? = nil,
        errorSound: (any PlayableSound)? = nil
    ) {
        self.recordingStartedSound = recordingStartedSound
            ?? Self.makeSound(named: NSSound.Name("Funk"))
        self.recordingStoppedSound = recordingStoppedSound
            ?? Self.makeSound(named: NSSound.Name("Bottle"))
        self.errorSound = errorSound
            ?? Self.makeSound(named: NSSound.Name("Basso"))
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

    private func restart(_ sound: (any PlayableSound)?) {
        guard let sound else {
            return
        }

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
