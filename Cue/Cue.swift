import AppKit
import AVFAudio
import FluidAudio
import KeyboardShortcuts
import Observation

private let pushToTalk = KeyboardShortcuts.Shortcut(.space, modifiers: [.option])

@MainActor
@Observable
final class Cue {
    typealias PreparationProgressHandler = @MainActor @Sendable (String) -> Void
    typealias EventType = KeyboardShortcuts.EventType

    enum Signal: Equatable {
        case started
        case stopped
    }

    enum Status: Equatable {
        case preparing(String)
        case ready
        case recording
        case transcribing
        case blocked(String)
    }

    private(set) var status: Status = .preparing("Checking Cue requirements…")

    private let prepare: @MainActor (@escaping PreparationProgressHandler) async throws -> Void
    private let events: AsyncStream<EventType>
    private let frontmostApplication: @MainActor () -> pid_t?
    private let startRecording: @MainActor () async throws -> Void
    private let stopRecording: @MainActor () async throws -> String
    private let signal: @MainActor (Signal) -> Void
    private let paste: @MainActor (String, pid_t) throws -> Void

    private var targetApplication: pid_t?
    private var transcription: Task<Void, Never>?
    private var isPrepared = false
    private var preparationAttempt = 0

    init(
        prepare: @escaping @MainActor (@escaping PreparationProgressHandler) async throws -> Void,
        events: AsyncStream<EventType>,
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
            prepare: { progress in
                progress("Checking microphone access…")
                guard await AVAudioApplication.requestRecordPermission() else {
                    throw Failure(errorDescription: "Microphone access is required. Grant it in System Settings, then hold ⌥Space.")
                }
                progress("Checking accessibility access…")
                guard CGRequestPostEventAccess() else {
                    throw Failure(errorDescription: "Accessibility access is required. Grant it in System Settings, then hold ⌥Space.")
                }
                progress("Checking Parakeet model files…")
                try await parakeet.prepare(progress: progress)
            },
            events: KeyboardShortcuts.events(for: pushToTalk),
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
            case .keyDown:
                if case .blocked = status {
                    await prepareIfNeeded()
                }
                await beginDictation()
            case .keyUp:
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

        preparationAttempt += 1
        let attempt = preparationAttempt
        status = .preparing("Checking Cue requirements…")
        do {
            try await prepare { [weak self] message in
                guard
                    let self,
                    self.preparationAttempt == attempt,
                    case .preparing = self.status
                else {
                    return
                }

                let nextStatus = Status.preparing(message)
                if self.status != nextStatus {
                    self.status = nextStatus
                }
            }
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

    private static func paste(_ text: String, into processIdentifier: pid_t) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw Failure(errorDescription: "Cue could not copy the transcript.")
        }

        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true),
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false),
            let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false)
        else {
            throw Failure(errorDescription: "Cue copied the transcript but could not paste it.")
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
        case .preparing(let message):
            message
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

    func prepare(progress: @escaping Cue.PreparationProgressHandler) async throws {
        let (updates, continuation) = AsyncStream.makeStream(
            of: DownloadProgress.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let relay = Task { @MainActor in
            for await update in updates {
                progress(Self.progressMessage(for: update))
            }
        }

        do {
            let models = try await AsrModels.downloadAndLoad(
                version: .v3,
                progressHandler: { continuation.yield($0) }
            )
            continuation.finish()
            await relay.value
            manager = AsrManager(config: .default, models: models)
        } catch {
            continuation.finish()
            await relay.value
            throw error
        }
    }

    private nonisolated static func progressMessage(for progress: DownloadProgress) -> String {
        switch progress.phase {
        case .listing:
            "Checking Parakeet model files…"
        case .downloading(let completedFiles, let totalFiles):
            if totalFiles == 0 {
                "Loading cached Parakeet models…"
            } else {
                "Downloading Parakeet model files (\(completedFiles) of \(totalFiles))…"
            }
        case .compiling(let modelName):
            loadingMessage(for: modelName)
        @unknown default:
            "Preparing Parakeet models…"
        }
    }

    private nonisolated static func loadingMessage(for modelName: String) -> String {
        let model = URL(fileURLWithPath: modelName).deletingPathExtension().lastPathComponent
        guard !model.isEmpty else {
            return "Finishing Parakeet setup…"
        }

        let component: String
        switch model.lowercased() {
        case let name where name.contains("preprocessor"):
            component = "Preprocessor"
        case let name where name.contains("encoder"):
            component = "Encoder"
        case let name where name.contains("jointdecision"):
            component = "Decoder"
        default:
            component = model
        }

        return "Loading Parakeet \(component)…"
    }

    func startRecording() throws {
        guard manager != nil, recorder == nil else {
            throw Failure(errorDescription: "Parakeet is not ready.")
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
            throw Failure(errorDescription: "Cue could not start recording.")
        }

        self.recorder = recorder
        recordingURL = url
    }

    func stopRecording() async throws -> String {
        guard let manager, let recorder, let recordingURL else {
            throw Failure(errorDescription: "Cue was not recording.")
        }

        recorder.stop()
        self.recorder = nil
        self.recordingURL = nil
        defer { try? FileManager.default.removeItem(at: recordingURL) }

        let decoderLayers = await manager.decoderLayerCount
        var decoderState = try TdtDecoderState(decoderLayers: decoderLayers)
        return try await manager.transcribe(recordingURL, decoderState: &decoderState).text
    }
}

private struct Failure: LocalizedError {
    let errorDescription: String?
}
