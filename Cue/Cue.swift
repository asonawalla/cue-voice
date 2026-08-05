import AppKit
import AVFAudio
import FluidAudio
import KeyboardShortcuts
import Observation

private let pushToTalk = KeyboardShortcuts.Name(
    "fixedPushToTalk",
    default: .init(.space, modifiers: [.option])
)

@MainActor
@Observable
final class Cue {
    enum Event: Sendable {
        case pressed
        case released
    }

    enum Signal: Equatable {
        case started
        case stopped
    }

    enum Status: Equatable {
        case preparing
        case ready
        case recording
        case transcribing
        case blocked(String)
    }

    private(set) var status: Status = .preparing

    private let prepare: @MainActor () async throws -> Void
    private let events: AsyncStream<Event>
    private let frontmostApplication: @MainActor () -> pid_t?
    private let startRecording: @MainActor () async throws -> Void
    private let stopRecording: @MainActor () async throws -> String
    private let signal: @MainActor (Signal) -> Void
    private let paste: @MainActor (String, pid_t) throws -> Void

    private var targetApplication: pid_t?
    private var transcription: Task<Void, Never>?
    private var isPrepared = false

    init(
        prepare: @escaping @MainActor () async throws -> Void,
        events: AsyncStream<Event>,
        frontmostApplication: @escaping @MainActor () -> pid_t?,
        startRecording: @escaping @MainActor () async throws -> Void,
        stopRecording: @escaping @MainActor () async throws -> String,
        signal: @escaping @MainActor (Signal) -> Void,
        paste: @escaping @MainActor (String, pid_t) throws -> Void
    ) {
        self.prepare = prepare
        self.events = events
        self.frontmostApplication = frontmostApplication
        self.startRecording = startRecording
        self.stopRecording = stopRecording
        self.signal = signal
        self.paste = paste
    }

    convenience init() {
        let parakeet = Parakeet()
        let startedSound = NSSound(named: NSSound.Name("Funk"))
        let stoppedSound = NSSound(named: NSSound.Name("Bottle"))

        self.init(
            prepare: {
                guard await AVAudioApplication.requestRecordPermission() else {
                    throw Failure("Microphone access is required. Grant it in System Settings, then hold ⌥Space.")
                }
                guard CGRequestPostEventAccess() else {
                    throw Failure("Accessibility access is required. Grant it in System Settings, then hold ⌥Space.")
                }
                try await parakeet.prepare()
            },
            events: Self.hotkeyEvents(),
            frontmostApplication: {
                NSWorkspace.shared.frontmostApplication?.processIdentifier
            },
            startRecording: {
                try await parakeet.startRecording()
            },
            stopRecording: {
                try await parakeet.stopRecording()
            },
            signal: { signal in
                let sound = signal == .started ? startedSound : stoppedSound
                sound?.stop()
                sound?.play()
            },
            paste: Self.paste
        )
    }

    func run() async {
        await prepareIfNeeded()

        for await event in events {
            switch event {
            case .pressed:
                if case .blocked = status {
                    await prepareIfNeeded()
                }
                await beginDictation()
            case .released:
                endDictation()
            }
        }

        await transcription?.value
    }

    private func prepareIfNeeded() async {
        guard !isPrepared else {
            status = .ready
            return
        }

        status = .preparing
        do {
            try await prepare()
            isPrepared = true
            status = .ready
        } catch {
            status = .blocked(error.localizedDescription)
        }
    }

    private func beginDictation() async {
        guard status == .ready, let processIdentifier = frontmostApplication() else {
            return
        }

        targetApplication = processIdentifier

        do {
            try await startRecording()
            status = .recording
            signal(.started)
        } catch {
            targetApplication = nil
            status = .blocked(error.localizedDescription)
        }
    }

    private func endDictation() {
        guard status == .recording, let processIdentifier = targetApplication else {
            return
        }

        targetApplication = nil
        signal(.stopped)
        status = .transcribing
        transcription = Task { [weak self] in
            await self?.finishDictation(in: processIdentifier)
        }
    }

    private func finishDictation(in processIdentifier: pid_t) async {
        do {
            let text = try await stopRecording().trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                try paste(text, processIdentifier)
            }
            status = .ready
        } catch {
            status = .blocked(error.localizedDescription)
        }
    }

    private static func hotkeyEvents() -> AsyncStream<Event> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                for await event in KeyboardShortcuts.events(for: pushToTalk) {
                    continuation.yield(event == .keyDown ? .pressed : .released)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func paste(_ text: String, into processIdentifier: pid_t) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw Failure("Cue could not copy the transcript.")
        }

        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true),
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false),
            let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false)
        else {
            throw Failure("Cue copied the transcript but could not paste it.")
        }

        commandDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand

        for event in [commandDown, vDown, vUp, commandUp] {
            event.postToPid(processIdentifier)
        }
    }
}

extension Cue.Status {
    var message: String {
        switch self {
        case .preparing:
            "Preparing Parakeet…"
        case .ready:
            "Ready — hold ⌥Space to dictate"
        case .recording:
            "Recording…"
        case .transcribing:
            "Transcribing…"
        case .blocked(let message):
            message
        }
    }

    var symbolName: String {
        switch self {
        case .preparing, .transcribing:
            "ellipsis"
        case .ready:
            "waveform"
        case .recording:
            "record.circle.fill"
        case .blocked:
            "exclamationmark.triangle"
        }
    }
}

private actor Parakeet {
    private var manager: AsrManager?
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    func prepare() async throws {
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        let manager = AsrManager(config: .default)
        try await manager.initialize(models: models)
        self.manager = manager
    }

    func startRecording() throws {
        guard manager != nil, recorder == nil else {
            throw Failure("Parakeet is not ready.")
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let recorder = try AVAudioRecorder(
            url: url,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
        )

        recorder.prepareToRecord()
        guard recorder.record() else {
            throw Failure("Cue could not start recording.")
        }

        self.recorder = recorder
        recordingURL = url
    }

    func stopRecording() async throws -> String {
        guard let manager, let recorder, let recordingURL else {
            throw Failure("Cue was not recording.")
        }

        recorder.stop()
        self.recorder = nil
        self.recordingURL = nil
        defer { try? FileManager.default.removeItem(at: recordingURL) }

        return try await manager.transcribe(recordingURL, source: .microphone).text
    }
}

private struct Failure: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}
