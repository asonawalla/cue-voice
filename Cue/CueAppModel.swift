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

    init(
        transcriptionService: TranscriptionService? = nil
    ) {
        self.transcriptionService = transcriptionService ?? WhisperKitTranscriptionService()

        self.transcriptionService.statusHandler = { [weak self] status in
            self?.modelStatus = status
        }
    }

    var isBusy: Bool {
        phase == .preparingModel || phase == .transcribing
    }

    var isRecording: Bool {
        phase == .recording
    }

    var isModelReady: Bool {
        modelStatus.isReady
    }

    var primaryButtonTitle: String {
        switch phase {
        case .preparingModel:
            return "Preparing Model..."
        case .recording:
            return "Stop Recording"
        case .transcribing:
            return "Transcribing..."
        default:
            return isModelReady ? "Start Recording" : "Prepare Model"
        }
    }

    var primaryButtonDisabled: Bool {
        phase == .preparingModel || phase == .transcribing
    }

    func bootstrap() async {
        guard !isModelReady, phase == .idle else {
            return
        }

        await prepareModel()
    }

    func handlePrimaryAction() async {
        if isRecording {
            await stopRecording()
        } else if isModelReady {
            await startRecording()
        } else {
            await prepareModel()
        }
    }

    func prepareModel() async {
        guard phase != .preparingModel else {
            return
        }

        errorMessage = nil
        phase = .preparingModel

        do {
            try await transcriptionService.prepareModel()
            phase = transcript.isEmpty ? .idle : .completed
        } catch {
            present(error)
        }
    }

    func startRecording() async {
        guard !isBusy else {
            present(CueError.busy)
            return
        }

        errorMessage = nil
        latencyMetrics = nil

        if !isModelReady {
            await prepareModel()
            guard isModelReady else {
                return
            }
        }

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
            phase = .completed

            logger.info(
                "Completed transcription. record=\(result.recordingDuration, format: .fixed(precision: 2))s transcribe=\(transcriptionDuration, format: .fixed(precision: 2))s total=\((result.recordingDuration + transcriptionDuration), format: .fixed(precision: 2))s"
            )
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
