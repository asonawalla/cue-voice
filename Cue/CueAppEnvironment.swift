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
        #if DEBUG
        if isUITesting {
            return makeUITesting()
        }
        #endif

        let model = CueAppModel()
        let hotkeyManager = CueHotkeyManager(appModel: model)
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
