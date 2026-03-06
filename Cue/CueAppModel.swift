import Foundation
import Observation
import os

@MainActor
@Observable
final class CueAppModel {
    var phase: CuePhase = .idle
    var modelStatus: ModelPreparationStatus = .idle
    var transcript = ""
    var errorMessage: String?
    var latencyMetrics: LatencyMetrics?

    private let transcriptionService: TranscriptionService
    private let logger = Logger(subsystem: "dev.sonawalla.Cue", category: "AppModel")
    private var hasLaunched = false
    private var isPreparingModel = false

    init(
        transcriptionService: TranscriptionService? = nil
    ) {
        self.transcriptionService = transcriptionService ?? WhisperKitTranscriptionService()

        self.transcriptionService.statusHandler = { [weak self] status in
            self?.modelStatus = status
        }
    }

    var isTranscribing: Bool {
        phase == .transcribing
    }

    var isRecording: Bool {
        phase == .recording
    }

    var isModelReady: Bool {
        modelStatus.isReady
    }

    var isModelPreparing: Bool {
        modelStatus.isPreparing
    }

    var shouldOfferModelRetry: Bool {
        !isModelReady && !isModelPreparing
    }

    var menuBarSymbolName: String {
        switch phase {
        case .recording:
            return "mic.circle.fill"
        case .transcribing:
            return "waveform.badge.magnifyingglass"
        case .error:
            return "exclamationmark.circle.fill"
        case .idle:
            return isModelReady ? "mic" : "ellipsis.circle"
        }
    }

    var menuBarPrimaryStatus: String {
        switch phase {
        case .idle:
            return isModelReady ? "Ready" : "Preparing Model"
        default:
            return phase.title
        }
    }

    var menuBarSecondaryStatus: String? {
        switch phase {
        case .recording:
            return "Release the shortcut to stop recording."
        case .transcribing:
            return "WhisperKit is transcribing the latest clip."
        case .error:
            return errorMessage
        case .idle:
            return isModelReady ? "Hold the push-to-talk shortcut in any app." : modelStatus.title
        }
    }

    func launch() async {
        guard !hasLaunched else {
            return
        }

        hasLaunched = true
        await warmModel()
    }

    func retryModelPreparation() async {
        await warmModel()
    }

    func handlePushToTalkPressed() async {
        guard phase != .recording, phase != .transcribing else {
            return
        }

        guard isModelReady else {
            logger.info("Ignoring push-to-talk press while model status is \(self.modelStatus.title, privacy: .public)")
            return
        }

        await startRecording()
    }

    func handlePushToTalkReleased() async {
        guard phase == .recording else {
            return
        }

        await stopRecording()
    }

    func startRecording() async {
        guard phase != .recording else {
            return
        }

        guard !isTranscribing else {
            logger.info("Ignoring record start while transcription is in progress")
            return
        }

        guard isModelReady else {
            logger.info("Ignoring record start because the model is not ready")
            return
        }

        errorMessage = nil
        latencyMetrics = nil

        do {
            try await transcriptionService.startRecording()
            phase = .recording
        } catch {
            present(error)
        }
    }

    func stopRecording() async {
        guard phase == .recording else {
            return
        }

        phase = .transcribing
        errorMessage = nil

        do {
            let startedAt = Date()
            let result = try await transcriptionService.stopRecording()
            let transcriptionDuration = Date().timeIntervalSince(startedAt)

            transcript = result.text
            latencyMetrics = LatencyMetrics(
                recordingDuration: result.recordingDuration,
                transcriptionDuration: transcriptionDuration,
                totalDuration: result.recordingDuration + transcriptionDuration,
                modelLoadDuration: result.modelLoadDuration,
                backendPipelineDuration: result.pipelineDuration
            )
            phase = .idle

            logger.info(
                "Completed transcription. record=\(result.recordingDuration, format: .fixed(precision: 2))s transcribe=\(transcriptionDuration, format: .fixed(precision: 2))s total=\((result.recordingDuration + transcriptionDuration), format: .fixed(precision: 2))s"
            )
        } catch {
            present(error)
        }
    }

    private func warmModel() async {
        guard !isPreparingModel else {
            return
        }

        guard !isModelReady else {
            if phase == .error {
                phase = .idle
                errorMessage = nil
            }
            return
        }

        isPreparingModel = true
        errorMessage = nil

        defer {
            isPreparingModel = false
        }

        do {
            try await transcriptionService.prepareModel()
            errorMessage = nil

            if phase == .error {
                phase = .idle
            }
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        let message: String
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            message = description
        } else {
            message = error.localizedDescription
        }

        errorMessage = message
        phase = .error
        logger.error("\(message, privacy: .public)")
    }
}
