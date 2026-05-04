import Foundation
import CoreML
import WhisperKit
import os

typealias TranscriptionStatusHandler = @MainActor @Sendable (ModelPreparationStatus) -> Void

nonisolated protocol TranscriptionService: AnyObject {
    @MainActor var statusHandler: TranscriptionStatusHandler? { get set }

    func prepareModel() async throws
    func startRecording() async throws
    func stopRecording() async throws -> CueTranscriptionResult
}

nonisolated final class WhisperKitTranscriptionService: TranscriptionService {
    @MainActor var statusHandler: TranscriptionStatusHandler?

    private let backend: WhisperKitTranscriptionBackend

    @MainActor
    init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        clientFactory: WhisperKitClientFactory? = nil,
        debugCaptureStore: (any DebugCaptureStoring)? = nil
    ) {
        backend = WhisperKitTranscriptionBackend(
            fileManager: fileManager,
            defaults: defaults,
            clientFactory: clientFactory ?? LiveWhisperKitClientFactory(),
            debugCaptureStore: debugCaptureStore
                ?? DebugCaptureStore(
                    fileManager: fileManager,
                    rootDirectory: CueAppConfiguration.debugCaptureRootDirectory(fileManager: fileManager)
                )
        )
    }

    func prepareModel() async throws {
        let statusHandler: TranscriptionStatusHandler? = await MainActor.run { self.statusHandler }
        try await backend.prepareModel(statusHandler: statusHandler)
    }

    func startRecording() async throws {
        let statusHandler: TranscriptionStatusHandler? = await MainActor.run { self.statusHandler }
        try await backend.startRecording(statusHandler: statusHandler)
    }

    func stopRecording() async throws -> CueTranscriptionResult {
        try await backend.stopRecording()
    }
}

@MainActor
private final class ModelPreparationStatusReporter {
    private let statusHandler: TranscriptionStatusHandler?
    private var acceptsDownloadProgress = false

    init(statusHandler: TranscriptionStatusHandler?) {
        self.statusHandler = statusHandler
    }

    func report(_ status: ModelPreparationStatus) {
        statusHandler?(status)
    }

    func beginDownload() {
        acceptsDownloadProgress = true
        report(.downloading(progress: nil))
    }

    func finishDownload() {
        acceptsDownloadProgress = false
    }

    func reportDownloadProgress(_ progress: Double) {
        guard acceptsDownloadProgress else {
            return
        }

        report(.downloading(progress: progress))
    }
}

private actor WhisperKitTranscriptionBackend {
    private static let ignoredTranscriptSentinels: Set<String> = [
        "[BLANK_AUDIO]"
    ]

    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let clientFactory: WhisperKitClientFactory
    private let debugCaptureStore: any DebugCaptureStoring
    private let logger = Logger(subsystem: "dev.sonawalla.Cue", category: "Transcription")

    private var whisperKitClient: (any WhisperKitClient)?
    private var recordingStartedAt: Date?

    init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        clientFactory: any WhisperKitClientFactory,
        debugCaptureStore: any DebugCaptureStoring
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.clientFactory = clientFactory
        self.debugCaptureStore = debugCaptureStore
    }

    func prepareModel(statusHandler: TranscriptionStatusHandler?) async throws {
        let statusReporter = await MainActor.run {
            ModelPreparationStatusReporter(statusHandler: statusHandler)
        }

        if whisperKitClient != nil {
            await statusReporter.report(.ready)
            return
        }

        let modelDirectory = CueAppConfiguration.modelDownloadDirectory(fileManager: fileManager)
        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        await statusReporter.report(.checkingCache)

        let modelFolder: URL
        if let cachedModelFolder = cachedModelFolder(), fileManager.fileExists(atPath: cachedModelFolder.path) {
            modelFolder = cachedModelFolder
        } else {
            await statusReporter.beginDownload()
            do {
                modelFolder = try await clientFactory.downloadModel(
                    variant: CueAppConfiguration.modelID,
                    downloadBase: modelDirectory
                ) { progress in
                    Task { @MainActor in
                        statusReporter.reportDownloadProgress(progress)
                    }
                }
                await statusReporter.finishDownload()
            } catch {
                await statusReporter.finishDownload()
                await statusReporter.report(.failed("Model download failed"))
                throw CueError.modelDownloadFailed(error.localizedDescription)
            }

            defaults.set(modelFolder.path, forKey: CueAppConfiguration.cachedModelPathDefaultsKey)
        }

        await statusReporter.report(.loading)

        do {
            whisperKitClient = try await clientFactory.makeClient(
                modelID: CueAppConfiguration.modelID,
                modelDirectory: modelDirectory,
                modelFolder: modelFolder
            )
        } catch {
            await statusReporter.report(.failed("Model load failed"))
            throw CueError.modelLoadFailed(error.localizedDescription)
        }

        await statusReporter.report(.ready)
        logger.info("WhisperKit model \(CueAppConfiguration.modelID, privacy: .public) ready from \(modelFolder.path, privacy: .public)")
    }

    func startRecording(statusHandler: TranscriptionStatusHandler?) async throws {
        guard recordingStartedAt == nil else {
            throw CueError.recordingAlreadyInProgress
        }

        try await prepareModel(statusHandler: statusHandler)

        guard let whisperKitClient else {
            throw CueError.transcriptionFailed("The WhisperKit pipeline was not available.")
        }

        do {
            try whisperKitClient.startRecording()
            recordingStartedAt = Date()
            logger.info("Recording started with WhisperKit audio processor")
        } catch let error as WhisperError {
            throw mapRecordingError(error)
        } catch {
            throw CueError.recordingFailed(error.localizedDescription)
        }
    }

    func stopRecording() async throws -> CueTranscriptionResult {
        guard let whisperKitClient else {
            throw CueError.noRecordingInProgress
        }

        guard recordingStartedAt != nil else {
            throw CueError.noRecordingInProgress
        }

        whisperKitClient.stopRecording()
        recordingStartedAt = nil

        let audioSamples = whisperKitClient.audioSamples
        let sampleCount = audioSamples.count
        let recordingDuration = Double(audioSamples.count) / Double(WhisperKit.sampleRate)

        logger.info(
            "Recording stopped after \(recordingDuration, format: .fixed(precision: 2)) seconds with \(sampleCount) samples"
        )

        guard recordingDuration >= CueAppConfiguration.minimumRecordingDuration else {
            throw CueError.recordingTooShort(
                actual: recordingDuration,
                minimum: CueAppConfiguration.minimumRecordingDuration
            )
        }

        let debugCapture = await createDebugCaptureIfNeeded(
            audioSamples: audioSamples,
            recordingDuration: recordingDuration
        )

        let results: [WhisperKitTranscriptionSegment]

        do {
            results = try await whisperKitClient.transcribe(audioSamples: audioSamples, language: "en")
        } catch {
            await saveDebugCaptureResult(
                for: debugCapture,
                sampleCount: sampleCount,
                recordingDuration: recordingDuration,
                segments: [],
                finalTranscript: "",
                errorMessage: error.localizedDescription
            )
            throw CueError.transcriptionFailed(error.localizedDescription)
        }

        let transcript = results
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let transcriptError: CueError?
        if transcript.isEmpty || Self.ignoredTranscriptSentinels.contains(transcript) {
            transcriptError = .emptyTranscript
        } else {
            transcriptError = nil
        }

        await saveDebugCaptureResult(
            for: debugCapture,
            sampleCount: sampleCount,
            recordingDuration: recordingDuration,
            segments: results,
            finalTranscript: transcript,
            errorMessage: transcriptError.map(CueCopy.errorMessage(for:))
        )

        if let transcriptError {
            throw transcriptError
        }

        return CueTranscriptionResult(
            text: transcript,
            language: results.first?.language ?? "en",
            recordingDuration: recordingDuration,
            modelLoadDuration: results.map(\.modelLoadDuration).max() ?? 0,
            pipelineDuration: results.map(\.pipelineDuration).reduce(0, +)
        )
    }

    private func mapRecordingError(_ error: WhisperError) -> CueError {
        switch error {
        case .microphoneUnavailable:
            return .missingMicrophoneInput
        case .audioProcessingFailed(let message):
            return .recordingFailed(message)
        default:
            return .recordingFailed(error.localizedDescription)
        }
    }

    private func cachedModelFolder() -> URL? {
        guard let cachedPath = defaults.string(forKey: CueAppConfiguration.cachedModelPathDefaultsKey) else {
            return nil
        }

        let cachedModelFolder = URL(fileURLWithPath: cachedPath)
        guard cachedModelFolder.lastPathComponent == CueAppConfiguration.expectedDownloadedModelFolderName(
            for: CueAppConfiguration.modelID
        ) else {
            return nil
        }

        return cachedModelFolder
    }

    private var shouldSaveDebugCaptures: Bool {
        defaults.bool(forKey: CueAppConfiguration.debugCapturesEnabledDefaultsKey)
    }

    private func createDebugCaptureIfNeeded(
        audioSamples: [Float],
        recordingDuration: TimeInterval
    ) async -> DebugCaptureHandle? {
        guard shouldSaveDebugCaptures else {
            return nil
        }

        do {
            let capture = try await debugCaptureStore.createCapture(
                audioSamples: audioSamples,
                recordingDuration: recordingDuration
            )
            logger.info("Saved debug capture audio to \(capture.directoryURL.path, privacy: .public)")
            return capture
        } catch {
            logger.error("Failed to save debug capture audio: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func saveDebugCaptureResult(
        for capture: DebugCaptureHandle?,
        sampleCount: Int,
        recordingDuration: TimeInterval,
        segments: [WhisperKitTranscriptionSegment],
        finalTranscript: String,
        errorMessage: String?
    ) async {
        guard let capture else {
            return
        }

        do {
            try await debugCaptureStore.saveResult(
                for: capture,
                sampleCount: sampleCount,
                recordingDuration: recordingDuration,
                segments: segments,
                finalTranscript: finalTranscript,
                errorMessage: errorMessage
            )
            logger.info("Saved debug capture result to \(capture.directoryURL.path, privacy: .public)")
        } catch {
            logger.error("Failed to save debug capture result: \(error.localizedDescription, privacy: .public)")
        }
    }
}

nonisolated protocol WhisperKitClientFactory {
    func downloadModel(
        variant: String,
        downloadBase: URL,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL

    func makeClient(
        modelID: String,
        modelDirectory: URL,
        modelFolder: URL
    ) async throws -> any WhisperKitClient
}

nonisolated protocol WhisperKitClient: AnyObject {
    var audioSamples: [Float] { get }

    func startRecording() throws
    func stopRecording()
    func transcribe(audioSamples: [Float], language: String) async throws -> [WhisperKitTranscriptionSegment]
}

struct WhisperKitTranscriptionSegment: Equatable, Sendable {
    let text: String
    let language: String?
    let modelLoadDuration: TimeInterval
    let pipelineDuration: TimeInterval
}

private nonisolated final class LiveWhisperKitClientFactory: WhisperKitClientFactory {
    func downloadModel(
        variant: String,
        downloadBase: URL,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {
        try await WhisperKit.download(variant: variant, downloadBase: downloadBase) { progress in
            onProgress(progress.fractionCompleted)
        }
    }

    func makeClient(
        modelID: String,
        modelDirectory: URL,
        modelFolder: URL
    ) async throws -> any WhisperKitClient {
        let config = WhisperKitConfig(
            model: modelID,
            downloadBase: modelDirectory,
            modelFolder: modelFolder.path,
            computeOptions: ModelComputeOptions(
                audioEncoderCompute: .cpuAndGPU,
                textDecoderCompute: .cpuAndGPU
            ),
            verbose: false,
            logLevel: .none,
            load: true,
            download: false
        )

        return LiveWhisperKitClient(whisperKit: try await WhisperKit(config))
    }
}

private nonisolated final class LiveWhisperKitClient: WhisperKitClient {
    private let whisperKit: WhisperKit

    init(whisperKit: WhisperKit) {
        self.whisperKit = whisperKit
    }

    var audioSamples: [Float] {
        Array(whisperKit.audioProcessor.audioSamples)
    }

    func startRecording() throws {
        try whisperKit.audioProcessor.startRecordingLive(inputDeviceID: nil, callback: nil)
    }

    func stopRecording() {
        whisperKit.audioProcessor.stopRecording()
    }

    func transcribe(audioSamples: [Float], language: String) async throws -> [WhisperKitTranscriptionSegment] {
        let options = DecodingOptions(
            verbose: false,
            language: language,
            detectLanguage: false,
            withoutTimestamps: true,
            wordTimestamps: false
        )

        let results = try await whisperKit.transcribe(audioArray: audioSamples, decodeOptions: options)
        return results.map { result in
            WhisperKitTranscriptionSegment(
                text: result.text,
                language: result.language,
                modelLoadDuration: result.timings.modelLoading,
                pipelineDuration: result.timings.fullPipeline
            )
        }
    }
}
