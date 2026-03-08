import Foundation
import WhisperKit
import os

@MainActor
protocol TranscriptionService: AnyObject {
    var statusHandler: ((ModelPreparationStatus) -> Void)? { get set }

    func prepareModel() async throws
    func startRecording() async throws
    func stopRecording() async throws -> CueTranscriptionResult
}

@MainActor
final class WhisperKitTranscriptionService: TranscriptionService {
    var statusHandler: ((ModelPreparationStatus) -> Void)?

    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let clientFactory: WhisperKitClientFactory
    private let logger = Logger(subsystem: "dev.sonawalla.Cue", category: "Transcription")

    private var whisperKitClient: (any WhisperKitClient)?
    private var recordingStartedAt: Date?

    init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        clientFactory: WhisperKitClientFactory? = nil
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.clientFactory = clientFactory ?? LiveWhisperKitClientFactory()
    }

    func prepareModel() async throws {
        if whisperKitClient != nil {
            statusHandler?(.ready)
            return
        }

        let modelDirectory = CueAppConfiguration.modelDownloadDirectory
        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        statusHandler?(.checkingCache)

        let modelFolder: URL
        if let cachedModelFolder = cachedModelFolder(), fileManager.fileExists(atPath: cachedModelFolder.path) {
            modelFolder = cachedModelFolder
        } else {
            statusHandler?(.downloading(progress: nil))
            do {
                modelFolder = try await clientFactory.downloadModel(
                    variant: CueAppConfiguration.modelID,
                    downloadBase: modelDirectory
                ) { [weak self] progress in
                    self?.statusHandler?(.downloading(progress: progress))
                }
            } catch {
                statusHandler?(.failed("Model download failed"))
                throw CueError.modelDownloadFailed(error.localizedDescription)
            }

            defaults.set(modelFolder.path, forKey: CueAppConfiguration.cachedModelPathDefaultsKey)
        }

        statusHandler?(.loading)

        do {
            whisperKitClient = try await clientFactory.makeClient(
                modelID: CueAppConfiguration.modelID,
                modelDirectory: modelDirectory,
                modelFolder: modelFolder
            )
        } catch {
            statusHandler?(.failed("Model load failed"))
            throw CueError.modelLoadFailed(error.localizedDescription)
        }

        statusHandler?(.ready)
        logger.info("WhisperKit model ready from \(modelFolder.path, privacy: .public)")
    }

    func startRecording() async throws {
        guard recordingStartedAt == nil else {
            throw CueError.recordingAlreadyInProgress
        }

        try await prepareModel()

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
        let recordingDuration = Double(audioSamples.count) / Double(WhisperKit.sampleRate)

        logger.info("Recording stopped after \(recordingDuration, format: .fixed(precision: 2)) seconds")

        guard recordingDuration >= CueAppConfiguration.minimumRecordingDuration else {
            throw CueError.recordingTooShort(
                actual: recordingDuration,
                minimum: CueAppConfiguration.minimumRecordingDuration
            )
        }

        do {
            let results = try await whisperKitClient.transcribe(audioSamples: audioSamples, language: "en")
            let transcript = results
                .map(\.text)
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !transcript.isEmpty else {
                throw CueError.emptyTranscript
            }

            return CueTranscriptionResult(
                text: transcript,
                language: results.first?.language ?? "en",
                recordingDuration: recordingDuration,
                modelLoadDuration: results.map(\.modelLoadDuration).max() ?? 0,
                pipelineDuration: results.map(\.pipelineDuration).reduce(0, +)
            )
        } catch let cueError as CueError {
            throw cueError
        } catch {
            throw CueError.transcriptionFailed(error.localizedDescription)
        }
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

        return URL(fileURLWithPath: cachedPath)
    }
}

protocol WhisperKitClientFactory {
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

protocol WhisperKitClient: AnyObject {
    var audioSamples: [Float] { get }

    func startRecording() throws
    func stopRecording()
    func transcribe(audioSamples: [Float], language: String) async throws -> [WhisperKitTranscriptionSegment]
}

struct WhisperKitTranscriptionSegment: Equatable {
    let text: String
    let language: String?
    let modelLoadDuration: TimeInterval
    let pipelineDuration: TimeInterval
}

private final class LiveWhisperKitClientFactory: WhisperKitClientFactory {
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
            verbose: false,
            logLevel: .none,
            load: true,
            download: false
        )

        return LiveWhisperKitClient(whisperKit: try await WhisperKit(config))
    }
}

private final class LiveWhisperKitClient: WhisperKitClient {
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
