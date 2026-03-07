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
    private let logger = Logger(subsystem: "dev.sonawalla.Cue", category: "Transcription")

    private var whisperKit: WhisperKit?
    private var recordingStartedAt: Date?

    init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
    }

    func prepareModel() async throws {
        if whisperKit != nil {
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
                modelFolder = try await WhisperKit.download(
                    variant: CueAppConfiguration.modelID,
                    downloadBase: modelDirectory
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.statusHandler?(.downloading(progress: progress.fractionCompleted))
                    }
                }
            } catch {
                statusHandler?(.failed("Model download failed"))
                throw CueError.modelDownloadFailed(error.localizedDescription)
            }

            defaults.set(modelFolder.path, forKey: CueAppConfiguration.cachedModelPathDefaultsKey)
        }

        statusHandler?(.loading)

        do {
            let config = WhisperKitConfig(
                model: CueAppConfiguration.modelID,
                downloadBase: modelDirectory,
                modelFolder: modelFolder.path,
                verbose: false,
                logLevel: .none,
                load: true,
                download: false
            )
            whisperKit = try await WhisperKit(config)
        } catch {
            statusHandler?(.failed("Model load failed"))
            throw CueError.modelDownloadFailed(error.localizedDescription)
        }

        statusHandler?(.ready)
        logger.info("WhisperKit model ready from \(modelFolder.path, privacy: .public)")
    }

    func startRecording() async throws {
        guard recordingStartedAt == nil else {
            throw CueError.recordingAlreadyInProgress
        }

        try await prepareModel()

        guard let whisperKit else {
            throw CueError.transcriptionFailed("The WhisperKit pipeline was not available.")
        }

        do {
            try whisperKit.audioProcessor.startRecordingLive(inputDeviceID: nil, callback: nil)
            recordingStartedAt = Date()
            logger.info("Recording started with WhisperKit audio processor")
        } catch let error as WhisperError {
            throw mapRecordingError(error)
        } catch {
            throw CueError.recordingFailed(error.localizedDescription)
        }
    }

    func stopRecording() async throws -> CueTranscriptionResult {
        guard let whisperKit else {
            throw CueError.noRecordingInProgress
        }

        guard recordingStartedAt != nil else {
            throw CueError.noRecordingInProgress
        }

        whisperKit.audioProcessor.stopRecording()
        recordingStartedAt = nil

        let audioSamples = Array(whisperKit.audioProcessor.audioSamples)
        let recordingDuration = Double(audioSamples.count) / Double(WhisperKit.sampleRate)

        logger.info("Recording stopped after \(recordingDuration, format: .fixed(precision: 2)) seconds")

        guard recordingDuration >= CueAppConfiguration.minimumRecordingDuration else {
            throw CueError.recordingTooShort(
                actual: recordingDuration,
                minimum: CueAppConfiguration.minimumRecordingDuration
            )
        }

        let options = DecodingOptions(
            verbose: false,
            language: "en",
            detectLanguage: false,
            withoutTimestamps: true,
            wordTimestamps: false
        )

        do {
            let results = try await whisperKit.transcribe(audioArray: audioSamples, decodeOptions: options)
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
                modelLoadDuration: results.map(\.timings.modelLoading).max() ?? 0,
                pipelineDuration: results.map(\.timings.fullPipeline).reduce(0, +)
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
