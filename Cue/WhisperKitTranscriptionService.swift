import Foundation
import CoreML
import WhisperKit
import os

typealias TranscriptionStatusHandler = @MainActor @Sendable (ModelPreparationStatus) -> Void
enum TranscriptionPreviewUpdate: Sendable, Equatable {
    case text(String)
    case unavailable
}

typealias TranscriptionPreviewHandler = @MainActor @Sendable (TranscriptionPreviewUpdate) -> Void
typealias RecordingAudioBufferHandler = @Sendable ([Float]) -> Void

nonisolated struct WhisperKitStreamingHypothesis: Sendable, Equatable {
    let text: String
    let segments: [WhisperKitTranscriptionSegment]
    let words: [WhisperKitWordTiming]

    init(
        text: String,
        segments: [WhisperKitTranscriptionSegment],
        words: [WhisperKitWordTiming] = []
    ) {
        self.text = text
        self.segments = segments
        self.words = words
    }
}

nonisolated struct WhisperKitWordTiming: Codable, Sendable, Equatable {
    let text: String
    let start: Float
    let end: Float
}

nonisolated protocol TranscriptionService: AnyObject {
    func prepareModel(reportStatus: @escaping TranscriptionStatusHandler) async throws
    func prepareRecordingPreview() async
    func disableRecordingPreview() async
    func startRecording(reportPreview: TranscriptionPreviewHandler?) async throws
    func stopRecording(saveDebugCapture: Bool) async throws -> String
}

nonisolated extension TranscriptionService {
    func prepareRecordingPreview() async {}
    func disableRecordingPreview() async {}

    func startRecording() async throws {
        try await startRecording(reportPreview: nil)
    }
}

@MainActor
private final class ModelPreparationStatusReporter {
    private let statusHandler: TranscriptionStatusHandler
    private var acceptsDownloadProgress = false

    init(statusHandler: @escaping TranscriptionStatusHandler) {
        self.statusHandler = statusHandler
    }

    func report(_ status: ModelPreparationStatus) {
        statusHandler(status)
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

actor WhisperKitTranscriptionService: TranscriptionService {
    private static let ignoredTranscriptSentinels: Set<String> = [
        "[BLANK_AUDIO]"
    ]

    private let defaults: UserDefaults
    private let modelDirectory: URL
    private let clientFactory: WhisperKitClientFactory
    private let debugCaptureStore: any DebugCaptureStoring
    private let previewInterval: Duration
    private let previewMinimumSampleDelta: Int
    private let logger = Logger(subsystem: CueAppConfiguration.bundleIdentifier, category: "Transcription")

    private var whisperKitClient: (any WhisperKitClient)?
    private var loadedModelFolder: URL?
    private var previewWhisperKitClient: (any WhisperKitClient)?
    private var previewClientPreparationTask: Task<any WhisperKitClient, Error>?
    private var previewClientPreparationID: UUID?
    private var previewClientPreparationGeneration: UInt64?
    private var previewClientGeneration: UInt64 = 0
    private var isRecordingPreviewEnabled = false
    private var isRecording = false
    private var previewTask: Task<Void, Never>?
    private var isStreamingInferenceInFlight = false
    private var streamingInferenceThroughSampleCount = 0
    private var recordingPreviewID: UUID?
    private var streamingTranscript = StreamingTranscriptAccumulator()

    private var needsPreviewClient: Bool {
        isRecordingPreviewEnabled || recordingPreviewID != nil
    }

    init(
        defaults: UserDefaults,
        modelDirectory: URL,
        clientFactory: any WhisperKitClientFactory,
        debugCaptureStore: any DebugCaptureStoring,
        previewInterval: Duration = .milliseconds(100),
        previewMinimumSampleDelta: Int = WhisperKit.sampleRate / 2
    ) {
        self.defaults = defaults
        self.modelDirectory = modelDirectory
        self.clientFactory = clientFactory
        self.debugCaptureStore = debugCaptureStore
        self.previewInterval = previewInterval
        self.previewMinimumSampleDelta = previewMinimumSampleDelta
    }

    static func live(
        defaults: UserDefaults,
        modelDirectory: URL,
        debugCaptureDirectory: URL
    ) -> WhisperKitTranscriptionService {
        WhisperKitTranscriptionService(
            defaults: defaults,
            modelDirectory: modelDirectory,
            clientFactory: LiveWhisperKitClientFactory(),
            debugCaptureStore: DebugCaptureStore(rootDirectory: debugCaptureDirectory)
        )
    }

    func prepareModel(reportStatus: @escaping TranscriptionStatusHandler) async throws {
        let statusReporter = await MainActor.run {
            ModelPreparationStatusReporter(statusHandler: reportStatus)
        }

        if whisperKitClient != nil {
            return
        }

        do {
            try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        } catch {
            throw CueError.modelDownloadFailed(error.localizedDescription)
        }

        await statusReporter.report(.checkingCache)

        let modelFolder: URL
        if let cachedModelFolder = cachedModelFolder(), FileManager.default.fileExists(atPath: cachedModelFolder.path) {
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
            loadedModelFolder = modelFolder
        } catch {
            throw CueError.modelLoadFailed(error.localizedDescription)
        }

        logger.info("WhisperKit model \(CueAppConfiguration.modelID, privacy: .public) ready from \(modelFolder.path, privacy: .public)")
    }

    func startRecording(reportPreview: TranscriptionPreviewHandler?) async throws {
        guard !isRecording else {
            throw CueError.recordingAlreadyInProgress
        }

        guard let whisperKitClient else {
            throw CueError.transcriptionFailed("The WhisperKit pipeline was not available.")
        }

        let previewID = reportPreview.map { _ in UUID() }
        recordingPreviewID = previewID
        streamingTranscript = StreamingTranscriptAccumulator()
        isStreamingInferenceInFlight = false
        streamingInferenceThroughSampleCount = 0

        if previewID != nil {
            isRecordingPreviewEnabled = true
        }

        let previewBuffer = reportPreview.map { _ in
            RecordingAudioBuffer()
        }
        let onAudioBuffer: RecordingAudioBufferHandler?
        if let previewBuffer {
            onAudioBuffer = { @Sendable samples in
                previewBuffer.append(samples)
            }
        } else {
            onAudioBuffer = nil
        }

        do {
            try whisperKitClient.startRecording(onAudioBuffer: onAudioBuffer)
            isRecording = true

            if let reportPreview, let previewBuffer, let previewID {
                let precedingPreviewTask = previewTask
                previewTask = Task(priority: .utility) { [weak self] in
                    await precedingPreviewTask?.value
                    guard !Task.isCancelled else {
                        return
                    }

                    await self?.reportRecordingPreviews(
                        from: previewBuffer,
                        previewID: previewID,
                        reportPreview: reportPreview
                    )
                }
            }

            logger.info("Recording started with WhisperKit audio processor")
        } catch let error as WhisperError {
            recordingPreviewID = nil
            throw mapRecordingError(error)
        } catch {
            recordingPreviewID = nil
            throw CueError.recordingFailed(error.localizedDescription)
        }
    }

    func prepareRecordingPreview() async {
        guard whisperKitClient != nil else {
            return
        }

        isRecordingPreviewEnabled = true

        do {
            _ = try await preparePreviewClient()
        } catch {
            logger.debug("Live transcript preview could not be prepared: \(error.localizedDescription, privacy: .public)")
        }
    }

    func disableRecordingPreview() async {
        isRecordingPreviewEnabled = false

        // An active streaming transcript is also the fast final result. Hiding
        // the pill must not discard that work and force a whole-clip retry.
        guard !isRecording, recordingPreviewID == nil else {
            return
        }

        previewClientGeneration &+= 1
        previewTask?.cancel()
        previewClientPreparationTask?.cancel()
        previewWhisperKitClient = nil
        recordingPreviewID = nil
    }

    func stopRecording(saveDebugCapture: Bool) async throws -> String {
        guard let whisperKitClient else {
            throw CueError.noRecordingInProgress
        }

        guard isRecording else {
            throw CueError.noRecordingInProgress
        }

        let hadStreamingSession = recordingPreviewID != nil
        let activePreviewTask = previewTask

        whisperKitClient.stopRecording()
        isRecording = false
        let audioSamples = whisperKitClient.audioSamples

        var inFlightRemainderWasSilence = false
        let inFlightThroughSampleCount = streamingInferenceThroughSampleCount
        if isStreamingInferenceInFlight,
           inFlightThroughSampleCount < audioSamples.count {
            let remainder = Array(audioSamples.dropFirst(inFlightThroughSampleCount))
            inFlightRemainderWasSilence = !whisperKitClient.hasVoiceActivity(in: remainder)
        }

        // Let an inference already in flight finish when it is the first useful
        // hypothesis or there is not yet a confirmed boundary for a bounded
        // tail decode. This avoids replacing useful streaming work with a
        // second whole-recording pass on release.
        let shouldAwaitInFlightInference = isStreamingInferenceInFlight
            && (
                inFlightThroughSampleCount >= audioSamples.count
                    || inFlightRemainderWasSilence
                    || streamingTranscript.latestTranscript.isEmpty
                    || !streamingTranscript.canFinalizeFromConfirmedBoundary
            )
        if !shouldAwaitInFlightInference {
            activePreviewTask?.cancel()
        }
        await activePreviewTask?.value
        if inFlightRemainderWasSilence,
           streamingTranscript.coveredSampleCount >= inFlightThroughSampleCount {
            streamingTranscript.markNoSpeech(throughSampleCount: audioSamples.count)
        }
        // Retain the session's client before making the preview disposable.
        // The setting can now be toggled while tail finalization awaits without
        // forcing this recording onto the primary whole-clip path.
        let finalizationPreviewClient = previewWhisperKitClient
        previewTask = nil
        recordingPreviewID = nil
        isStreamingInferenceInFlight = false
        streamingInferenceThroughSampleCount = 0

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

        let debugCapture = createDebugCaptureIfNeeded(
            audioSamples: audioSamples,
            enabled: saveDebugCapture
        )

        let transcription: (text: String, segments: [WhisperKitTranscriptionSegment])

        do {
            if hadStreamingSession, let previewClient = finalizationPreviewClient {
                do {
                    transcription = try await finalizeStreamingTranscript(
                        audioSamples: audioSamples,
                        recordingClient: whisperKitClient,
                        streamingClient: previewClient
                    )
                } catch {
                    if streamingTranscript.latestTranscript.isEmpty {
                        logger.error(
                            "The first streaming transcription failed; using whole-clip fallback: \(error.localizedDescription, privacy: .public)"
                        )
                        let results = try await whisperKitClient.transcribe(audioSamples: audioSamples)
                        transcription = (Self.transcript(from: results), results)
                    } else {
                        logger.error(
                            "Streaming tail refinement failed; keeping the latest cumulative transcript: \(error.localizedDescription, privacy: .public)"
                        )
                        transcription = (
                            streamingTranscript.latestTranscript,
                            streamingTranscript.debugSegments
                        )
                    }
                }
            } else {
                let results = try await whisperKitClient.transcribe(audioSamples: audioSamples)
                transcription = (Self.transcript(from: results), results)
            }
        } catch {
            saveDebugCaptureResult(
                for: debugCapture,
                sampleCount: sampleCount,
                recordingDuration: recordingDuration,
                segments: [],
                finalTranscript: "",
                errorMessage: error.localizedDescription
            )
            throw CueError.transcriptionFailed(error.localizedDescription)
        }

        let transcript = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)

        let transcriptError: CueError?
        if transcript.isEmpty || Self.ignoredTranscriptSentinels.contains(transcript) {
            transcriptError = .emptyTranscript
        } else {
            transcriptError = nil
        }

        saveDebugCaptureResult(
            for: debugCapture,
            sampleCount: sampleCount,
            recordingDuration: recordingDuration,
            segments: transcription.segments,
            finalTranscript: transcript,
            errorMessage: transcriptError.map(CueCopy.errorMessage(for:))
        )

        if !isRecordingPreviewEnabled {
            previewClientGeneration &+= 1
            previewWhisperKitClient = nil
        }

        if let transcriptError {
            throw transcriptError
        }

        return transcript
    }

    private func reportRecordingPreviews(
        from previewBuffer: RecordingAudioBuffer,
        previewID: UUID,
        reportPreview: @escaping TranscriptionPreviewHandler
    ) async {
        let previewClient: any WhisperKitClient
        do {
            previewClient = try await preparePreviewClient()
        } catch is CancellationError {
            return
        } catch {
            logger.debug("Live transcript preview was unavailable: \(error.localizedDescription, privacy: .public)")
            await reportPreview(.unavailable)
            return
        }

        guard recordingPreviewID == previewID, isRecording, !Task.isCancelled else {
            return
        }

        guard let recordingClient = whisperKitClient else {
            return
        }

        var lastAttemptedSampleCount = 0

        while recordingPreviewID == previewID, isRecording, !Task.isCancelled {
            guard recordingPreviewID == previewID, isRecording, !Task.isCancelled else {
                return
            }

            let availableSampleCount = previewBuffer.sampleCount
            guard availableSampleCount - lastAttemptedSampleCount >= previewMinimumSampleDelta else {
                do {
                    try await Task.sleep(for: previewInterval)
                } catch {
                    return
                }
                continue
            }

            let snapshot = previewBuffer.snapshot()
            let newSampleCount = snapshot.totalSampleCount - lastAttemptedSampleCount
            lastAttemptedSampleCount = snapshot.totalSampleCount
            let newAudio = Array(snapshot.samples.suffix(newSampleCount))

            guard recordingClient.hasVoiceActivity(in: newAudio) else {
                continue
            }

            do {
                isStreamingInferenceInFlight = true
                streamingInferenceThroughSampleCount = snapshot.totalSampleCount
                let hypothesis = try await previewClient.transcribeStreaming(
                    audioSamples: snapshot.samples,
                    startingAt: streamingTranscript.decodeStartSeconds
                )
                isStreamingInferenceInFlight = false
                streamingInferenceThroughSampleCount = 0
                guard recordingPreviewID == previewID, !Task.isCancelled else {
                    return
                }

                if let transcript = streamingTranscript.accept(
                    hypothesis,
                    throughSampleCount: snapshot.totalSampleCount
                ) {
                    await reportPreview(.text(transcript))
                }
            } catch is CancellationError {
                isStreamingInferenceInFlight = false
                streamingInferenceThroughSampleCount = 0
                return
            } catch {
                isStreamingInferenceInFlight = false
                streamingInferenceThroughSampleCount = 0
                logger.debug("Skipping live transcript preview update: \(error.localizedDescription, privacy: .public)")
                if recordingPreviewID == previewID, isRecording, !Task.isCancelled {
                    await reportPreview(.unavailable)
                }
            }
        }
    }

    private func finalizeStreamingTranscript(
        audioSamples: [Float],
        recordingClient: any WhisperKitClient,
        streamingClient: any WhisperKitClient
    ) async throws -> (text: String, segments: [WhisperKitTranscriptionSegment]) {
        let uncoveredSampleCount = max(0, audioSamples.count - streamingTranscript.coveredSampleCount)
        let uncoveredAudio = Array(audioSamples.suffix(uncoveredSampleCount))
        let uncoveredAudioHasVoice = uncoveredSampleCount > 0
            && recordingClient.hasVoiceActivity(in: uncoveredAudio)

        guard streamingTranscript.latestTranscript.isEmpty || uncoveredAudioHasVoice else {
            return (
                streamingTranscript.latestTranscript,
                streamingTranscript.debugSegments
            )
        }

        // With a useful cumulative hypothesis but no confirmed prefix, a tail
        // decode would necessarily start at zero and repeat the entire
        // recording. Keep the newest completed hypothesis instead. The small
        // uncovered tail may omit the final word, which is preferable to the
        // old release-time whole-recording pass.
        if !streamingTranscript.latestTranscript.isEmpty,
           !streamingTranscript.canFinalizeFromConfirmedBoundary {
            return (
                streamingTranscript.latestTranscript,
                streamingTranscript.debugSegments
            )
        }

        let finalHypothesis = try await streamingClient.transcribeStreaming(
            audioSamples: audioSamples,
            startingAt: streamingTranscript.finalizationDecodeStartSeconds
        )
        let transcript = streamingTranscript.finalTranscript(replacingTailWith: finalHypothesis)
        return (transcript, streamingTranscript.debugSegments(replacingTailWith: finalHypothesis))
    }

    private func preparePreviewClient() async throws -> any WhisperKitClient {
        while true {
            if let previewWhisperKitClient {
                return previewWhisperKitClient
            }

            guard needsPreviewClient else {
                throw CancellationError()
            }

            let preparationTask: Task<any WhisperKitClient, Error>
            let preparationID: UUID
            let preparationGeneration = previewClientGeneration

            if let existingTask = previewClientPreparationTask,
               let existingID = previewClientPreparationID {
                // A rapid re-enable adopts the still-running load instead of
                // starting a second model load alongside it.
                previewClientPreparationGeneration = preparationGeneration
                preparationTask = existingTask
                preparationID = existingID
            } else {
                guard let loadedModelFolder else {
                    throw CueError.transcriptionFailed("The WhisperKit preview pipeline was not available.")
                }

                let clientFactory = self.clientFactory
                let modelDirectory = self.modelDirectory
                preparationID = UUID()
                preparationTask = Task(priority: .utility) {
                    try await clientFactory.makeClient(
                        modelID: CueAppConfiguration.modelID,
                        modelDirectory: modelDirectory,
                        modelFolder: loadedModelFolder
                    )
                }
                previewClientPreparationTask = preparationTask
                previewClientPreparationID = preparationID
                previewClientPreparationGeneration = preparationGeneration
            }

            do {
                let client = try await preparationTask.value

                if let previewWhisperKitClient {
                    return previewWhisperKitClient
                }

                guard previewClientPreparationID == preparationID,
                      previewClientPreparationGeneration == preparationGeneration,
                      previewClientGeneration == preparationGeneration,
                      needsPreviewClient else {
                    throw CancellationError()
                }

                previewClientPreparationTask = nil
                previewClientPreparationID = nil
                previewClientPreparationGeneration = nil
                previewWhisperKitClient = client
                return client
            } catch {
                let ownsCurrentPreparation = previewClientPreparationID == preparationID
                    && previewClientPreparationGeneration == preparationGeneration

                if ownsCurrentPreparation {
                    previewClientPreparationTask = nil
                    previewClientPreparationID = nil
                    previewClientPreparationGeneration = nil
                }

                if error is CancellationError,
                   ownsCurrentPreparation,
                   previewClientGeneration == preparationGeneration,
                   needsPreviewClient,
                   !Task.isCancelled {
                    continue
                }

                throw error
            }
        }
    }

    private static func transcript(from segments: [WhisperKitTranscriptionSegment]) -> String {
        segments
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func createDebugCaptureIfNeeded(audioSamples: [Float], enabled: Bool) -> URL? {
        guard enabled else {
            return nil
        }

        do {
            let capture = try debugCaptureStore.createCapture(
                audioSamples: audioSamples
            )
            logger.info("Saved debug capture audio to \(capture.path, privacy: .public)")
            return capture
        } catch {
            logger.error("Failed to save debug capture audio: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func saveDebugCaptureResult(
        for capture: URL?,
        sampleCount: Int,
        recordingDuration: TimeInterval,
        segments: [WhisperKitTranscriptionSegment],
        finalTranscript: String,
        errorMessage: String?
    ) {
        guard let capture else {
            return
        }

        do {
            try debugCaptureStore.saveResult(
                for: capture,
                sampleCount: sampleCount,
                recordingDuration: recordingDuration,
                segments: segments,
                finalTranscript: finalTranscript,
                errorMessage: errorMessage
            )
            logger.info("Saved debug capture result to \(capture.path, privacy: .public)")
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

    func startRecording(onAudioBuffer: RecordingAudioBufferHandler?) throws
    func stopRecording()
    func hasVoiceActivity(in audioSamples: [Float]) -> Bool
    func transcribe(audioSamples: [Float]) async throws -> [WhisperKitTranscriptionSegment]
    func transcribeStreaming(
        audioSamples: [Float],
        startingAt seconds: Float
    ) async throws -> WhisperKitStreamingHypothesis
}

enum WhisperKitStreamingDecodingConfiguration {
    nonisolated static func makeOptions(startingAt seconds: Float) -> DecodingOptions {
        DecodingOptions(
            verbose: false,
            language: "en",
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: true,
            clipTimestamps: [max(0, seconds)],
            windowClipTime: 0
        )
    }
}

enum RecordingPreviewVoiceActivityDetector {
    // WhisperKit's default 0.02 RMS threshold is tuned too high for some
    // perfectly transcribable Mac microphone input. A false negative here
    // blocks live inference entirely, so the preview uses a deliberately
    // permissive threshold and lets transcription decide whether speech is
    // present.
    nonisolated static let energyThreshold: Float = 0.004

    nonisolated static func hasVoiceActivity(in audioSamples: [Float]) -> Bool {
        guard !audioSamples.isEmpty else {
            return false
        }

        return EnergyVAD(energyThreshold: energyThreshold)
            .voiceActivity(in: audioSamples)
            .contains(true)
    }
}

nonisolated struct StreamingTranscriptAccumulator: Sendable, Equatable {
    private static let wordAgreementCount = 2
    private static let revisableSegmentCount = 2
    private static let timestampTolerance: Float = 0.01

    private(set) var confirmedWords: [WhisperKitWordTiming] = []
    private(set) var previousHypothesisWords: [WhisperKitWordTiming] = []
    private(set) var revisableWords: [WhisperKitWordTiming] = []
    private(set) var confirmedSegments: [WhisperKitTranscriptionSegment] = []
    private(set) var revisableSegments: [WhisperKitTranscriptionSegment] = []
    private(set) var decodeStartSeconds: Float = 0
    private(set) var coveredSampleCount = 0
    private(set) var latestTranscript = ""

    var finalizationDecodeStartSeconds: Float {
        decodeStartSeconds
    }

    var canFinalizeFromConfirmedBoundary: Bool {
        decodeStartSeconds > Self.timestampTolerance
            && (!confirmedWords.isEmpty || !confirmedSegments.isEmpty)
    }

    var debugSegments: [WhisperKitTranscriptionSegment] {
        if hasWordTimingState {
            return Self.debugSegments(from: confirmedWords + revisableWords)
        }
        return confirmedSegments + revisableSegments
    }

    mutating func markNoSpeech(throughSampleCount sampleCount: Int) {
        coveredSampleCount = max(coveredSampleCount, sampleCount)
    }

    mutating func accept(
        _ hypothesis: WhisperKitStreamingHypothesis,
        throughSampleCount sampleCount: Int
    ) -> String? {
        let previousTranscript = latestTranscript

        if !hypothesis.words.isEmpty {
            acceptWords(from: hypothesis)
        } else {
            acceptSegments(from: hypothesis)
        }

        let candidateTranscript = hasWordTimingState
            ? Self.transcript(from: confirmedWords + revisableWords)
            : Self.transcript(from: debugSegments)
        if !candidateTranscript.isEmpty {
            latestTranscript = candidateTranscript
        } else if confirmedWords.isEmpty, confirmedSegments.isEmpty {
            let fallback = hypothesis.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallback.isEmpty {
                latestTranscript = fallback
            }
        }

        guard !latestTranscript.isEmpty, latestTranscript != previousTranscript else {
            return nil
        }
        // A completed inference only covers voiced audio when it produced a
        // useful new hypothesis. Empty or unchanged output must leave the
        // samples open for release-time tail handling.
        if let recognizedSampleCount = recognizedSampleCount(
            through: hypothesis,
            cappedAt: sampleCount
        ) {
            coveredSampleCount = recognizedSampleCount
        }
        return latestTranscript
    }

    func finalTranscript(replacingTailWith hypothesis: WhisperKitStreamingHypothesis) -> String {
        if hasWordTimingState {
            let finalWords = words(
                from: hypothesis,
                after: finalizationDecodeStartSeconds
            )
            if !finalWords.isEmpty {
                return Self.transcript(from: finalizationPrefixWords + finalWords)
            }

            let confirmedTranscript = Self.transcript(from: finalizationPrefixWords)
            let tailTranscript = hypothesis.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tailTranscript.isEmpty {
                return Self.join(confirmedTranscript, tailTranscript)
            }

            return latestTranscript
        }

        let replacementSegments = tailSegments(from: hypothesis)
        let replacementText = hypothesis.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if replacementSegments.isEmpty, replacementText.isEmpty {
            return latestTranscript
        }

        let segments = confirmedSegments + replacementSegments
        let segmentTranscript = Self.transcript(from: segments)
        if !segmentTranscript.isEmpty {
            return segmentTranscript
        }

        let confirmedTranscript = Self.transcript(from: confirmedSegments)
        let fallback = Self.join(confirmedTranscript, replacementText)
        return fallback.isEmpty ? latestTranscript : fallback
    }

    func debugSegments(
        replacingTailWith hypothesis: WhisperKitStreamingHypothesis
    ) -> [WhisperKitTranscriptionSegment] {
        if hasWordTimingState {
            let finalWords = words(
                from: hypothesis,
                after: finalizationDecodeStartSeconds
            )
            guard !finalWords.isEmpty else {
                return debugSegments
            }
            return Self.debugSegments(from: finalizationPrefixWords + finalWords)
        }

        let replacementSegments = tailSegments(from: hypothesis)
        guard !replacementSegments.isEmpty else {
            return debugSegments
        }
        return confirmedSegments + replacementSegments
    }

    private var hasWordTimingState: Bool {
        !confirmedWords.isEmpty || !previousHypothesisWords.isEmpty || !revisableWords.isEmpty
    }

    private var finalizationPrefixWords: [WhisperKitWordTiming] {
        confirmedWords
    }

    private func recognizedSampleCount(
        through hypothesis: WhisperKitStreamingHypothesis,
        cappedAt snapshotSampleCount: Int
    ) -> Int? {
        let latestWordEnd = hypothesis.words.map(\.end).max()
        let latestSegmentEnd = hypothesis.segments.map(\.end).max()
        guard let recognizedEndSeconds = [latestWordEnd, latestSegmentEnd]
            .compactMap({ $0 })
            .max(),
            recognizedEndSeconds > 0 else {
            return nil
        }

        let timedSampleCount = Int(
            (recognizedEndSeconds * Float(WhisperKit.sampleRate)).rounded(.down)
        )
        return min(snapshotSampleCount, max(0, timedSampleCount))
    }

    private mutating func acceptWords(from hypothesis: WhisperKitStreamingHypothesis) {
        let candidateWords = tailWords(from: hypothesis)
        guard !candidateWords.isEmpty else {
            return
        }

        confirmedSegments = []
        revisableSegments = []

        guard !previousHypothesisWords.isEmpty else {
            previousHypothesisWords = candidateWords
            revisableWords = candidateWords
            return
        }

        let commonPrefixCount = Self.commonPrefixCount(
            previousHypothesisWords,
            candidateWords
        )
        let confirmationCount = max(0, commonPrefixCount - Self.wordAgreementCount)

        if confirmationCount > 0 {
            let newlyConfirmed = Array(candidateWords.prefix(confirmationCount))
            confirmedWords.append(contentsOf: newlyConfirmed)

            let remainingWords = Array(candidateWords.dropFirst(confirmationCount))
            decodeStartSeconds = remainingWords.first?.start
                ?? newlyConfirmed.last?.end
                ?? decodeStartSeconds
            previousHypothesisWords = remainingWords
            revisableWords = remainingWords
        } else {
            previousHypothesisWords = candidateWords
            revisableWords = candidateWords
        }
    }

    private mutating func acceptSegments(from hypothesis: WhisperKitStreamingHypothesis) {
        let candidateSegments = tailSegments(from: hypothesis)

        if candidateSegments.count > Self.revisableSegmentCount {
            let confirmationCount = candidateSegments.count - Self.revisableSegmentCount
            let newlyConfirmed = Array(candidateSegments.prefix(confirmationCount))
            confirmedSegments.append(contentsOf: newlyConfirmed)
            decodeStartSeconds = newlyConfirmed.last?.end ?? decodeStartSeconds
            revisableSegments = Array(candidateSegments.suffix(Self.revisableSegmentCount))
        } else if !candidateSegments.isEmpty {
            revisableSegments = candidateSegments
        }
    }

    private func tailWords(
        from hypothesis: WhisperKitStreamingHypothesis
    ) -> [WhisperKitWordTiming] {
        words(from: hypothesis, after: decodeStartSeconds)
    }

    private func words(
        from hypothesis: WhisperKitStreamingHypothesis,
        after startSeconds: Float
    ) -> [WhisperKitWordTiming] {
        hypothesis.words.filter { word in
            word.start >= startSeconds - Self.timestampTolerance
                && word.end > startSeconds + Self.timestampTolerance
        }
    }

    private func tailSegments(
        from hypothesis: WhisperKitStreamingHypothesis
    ) -> [WhisperKitTranscriptionSegment] {
        hypothesis.segments.filter { segment in
            segment.end > decodeStartSeconds + Self.timestampTolerance
        }
    }

    private static func commonPrefixCount(
        _ previous: [WhisperKitWordTiming],
        _ current: [WhisperKitWordTiming]
    ) -> Int {
        zip(previous, current)
            .prefix { pair in
                normalize(pair.0.text) == normalize(pair.1.text)
            }
            .count
    }

    private static func normalize(_ word: String) -> String {
        word.trimmingCharacters(
            in: .whitespacesAndNewlines.union(.punctuationCharacters)
        ).lowercased()
    }

    private static func transcript(from words: [WhisperKitWordTiming]) -> String {
        words
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func transcript(from segments: [WhisperKitTranscriptionSegment]) -> String {
        segments
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func join(_ prefix: String, _ suffix: String) -> String {
        guard !prefix.isEmpty else { return suffix }
        guard !suffix.isEmpty else { return prefix }
        if suffix.first?.isWhitespace == true {
            return (prefix + suffix).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return prefix + " " + suffix
    }

    private static func debugSegments(
        from words: [WhisperKitWordTiming]
    ) -> [WhisperKitTranscriptionSegment] {
        words.map { word in
            WhisperKitTranscriptionSegment(
                text: word.text,
                language: nil,
                modelLoadDuration: 0,
                pipelineDuration: 0,
                start: word.start,
                end: word.end
            )
        }
    }
}

private nonisolated final class RecordingAudioBuffer: @unchecked Sendable {
    struct Snapshot: Sendable {
        let samples: [Float]
        let totalSampleCount: Int
    }

    private let lock = NSLock()
    private var chunks: [[Float]] = []
    private var totalSampleCount = 0

    var sampleCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return totalSampleCount
    }

    func append(_ newSamples: [Float]) {
        guard !newSamples.isEmpty else {
            return
        }

        lock.lock()
        defer { lock.unlock() }
        chunks.append(newSamples)
        totalSampleCount += newSamples.count
    }

    func snapshot() -> Snapshot {
        lock.lock()
        let snapshotChunks = chunks
        let snapshotSampleCount = totalSampleCount
        lock.unlock()

        var samples: [Float] = []
        samples.reserveCapacity(snapshotSampleCount)
        for chunk in snapshotChunks {
            samples.append(contentsOf: chunk)
        }
        return Snapshot(samples: samples, totalSampleCount: snapshotSampleCount)
    }
}

nonisolated struct WhisperKitTranscriptionSegment: Codable, Equatable, Sendable {
    let text: String
    let language: String?
    let modelLoadDuration: TimeInterval
    let pipelineDuration: TimeInterval
    let start: Float
    let end: Float

    init(
        text: String,
        language: String?,
        modelLoadDuration: TimeInterval,
        pipelineDuration: TimeInterval,
        start: Float = 0,
        end: Float = 0
    ) {
        self.text = text
        self.language = language
        self.modelLoadDuration = modelLoadDuration
        self.pipelineDuration = pipelineDuration
        self.start = start
        self.end = end
    }
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

    func startRecording(onAudioBuffer: RecordingAudioBufferHandler?) throws {
        try whisperKit.audioProcessor.startRecordingLive(inputDeviceID: nil, callback: onAudioBuffer)
    }

    func stopRecording() {
        whisperKit.audioProcessor.stopRecording()
    }

    func hasVoiceActivity(in audioSamples: [Float]) -> Bool {
        RecordingPreviewVoiceActivityDetector.hasVoiceActivity(in: audioSamples)
    }

    func transcribe(audioSamples: [Float]) async throws -> [WhisperKitTranscriptionSegment] {
        try await transcribe(
            audioSamples: audioSamples,
            options: DecodingOptions(
                verbose: false,
                language: "en",
                detectLanguage: false,
                withoutTimestamps: true,
                wordTimestamps: false
            )
        )
    }

    func transcribeStreaming(
        audioSamples: [Float],
        startingAt seconds: Float
    ) async throws -> WhisperKitStreamingHypothesis {
        let cancellationSignal = TranscriptionCancellationSignal()

        return try await withTaskCancellationHandler {
            let results = try await whisperKit.transcribe(
                audioArray: audioSamples,
                decodeOptions: WhisperKitStreamingDecodingConfiguration.makeOptions(startingAt: seconds),
                callback: { _ in !cancellationSignal.isCancelled }
            )
            let segments = results.flatMap { result in
                result.segments.map { segment in
                    WhisperKitTranscriptionSegment(
                        text: segment.text,
                        language: result.language,
                        modelLoadDuration: result.timings.modelLoading,
                        pipelineDuration: result.timings.fullPipeline,
                        start: segment.start,
                        end: segment.end
                    )
                }
            }
            let words = results.flatMap { result in
                result.allWords.map { word in
                    WhisperKitWordTiming(
                        text: word.word,
                        start: word.start,
                        end: word.end
                    )
                }
            }
            return WhisperKitStreamingHypothesis(
                text: results.map(\.text).joined(),
                segments: segments,
                words: words
            )
        } onCancel: {
            cancellationSignal.cancel()
        }
    }

    private func transcribe(
        audioSamples: [Float],
        options: DecodingOptions,
        shouldContinue: ((TranscriptionProgress) -> Bool?)? = nil
    ) async throws -> [WhisperKitTranscriptionSegment] {
        let results = try await whisperKit.transcribe(
            audioArray: audioSamples,
            decodeOptions: options,
            callback: shouldContinue
        )
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

private nonisolated final class TranscriptionCancellationSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
