import Foundation
import os

@MainActor
final class CueDictationCoordinator {
    private weak var stateStore: (any CueStateStore)?

    private let transcriptionService: TranscriptionService
    private let insertionService: TextInsertionService
    private let soundService: any SoundService
    private let logger = Logger(subsystem: "dev.sonawalla.Cue", category: "Dictation")

    init(
        transcriptionService: TranscriptionService,
        insertionService: TextInsertionService,
        soundService: any SoundService
    ) {
        self.transcriptionService = transcriptionService
        self.insertionService = insertionService
        self.soundService = soundService
    }

    func bind(to stateStore: any CueStateStore) {
        self.stateStore = stateStore
    }

    func handlePushToTalkPressed(using setupCoordinator: CueSetupCoordinator) async {
        guard let stateStore else {
            return
        }

        guard !stateStore.state.session.isBusy else {
            return
        }

        setupCoordinator.refreshPermissions()

        let state = stateStore.state

        if state.setup.permissions.microphone == .notDetermined {
            await setupCoordinator.runFirstUsePermissionBootstrap()
            return
        }

        guard state.setup.permissions.isMicrophoneReady else {
            logger.info("Ignoring push-to-talk press because microphone access is unavailable")
            present(CueError.microphonePermissionDenied)
            return
        }

        guard state.setup.permissions.isAccessibilityReady else {
            logger.info("Ignoring push-to-talk press because accessibility access is unavailable")
            present(CueError.accessibilityPermissionDenied)
            return
        }

        guard state.isModelReady else {
            logger.info("Ignoring push-to-talk press while model status is \(state.setup.modelStatus.title, privacy: .public)")
            await setupCoordinator.warmModel()
            return
        }

        await startRecording()
    }

    func handlePushToTalkReleased() async {
        guard stateStore?.state.session == .recording else {
            return
        }

        await stopRecording()
    }

    private func startRecording() async {
        guard let stateStore else {
            return
        }

        let state = stateStore.state

        guard state.session != .recording else {
            return
        }

        guard !state.session.isBusy else {
            logger.info("Ignoring record start while Cue is still transcribing or pasting")
            return
        }

        guard state.setup.permissions.isMicrophoneReady else {
            logger.info("Ignoring record start because microphone access is unavailable")
            present(CueError.microphonePermissionDenied)
            return
        }

        guard state.setup.permissions.isAccessibilityReady else {
            logger.info("Ignoring record start because accessibility access is unavailable")
            present(CueError.accessibilityPermissionDenied)
            return
        }

        guard state.isModelReady else {
            logger.info("Ignoring record start because the model is not ready")
            return
        }

        clearFailureForNewAttempt()
        soundService.playRecordingStarted()

        do {
            try await transcriptionService.startRecording()

            stateStore.updateState { updatedState in
                updatedState.session = .recording
            }
        } catch {
            present(error)
        }
    }

    private func stopRecording() async {
        guard let stateStore else {
            return
        }

        guard stateStore.state.session == .recording else {
            return
        }

        soundService.playRecordingStopped()

        stateStore.updateState { state in
            state.session = .transcribing
            state.latencyMetrics = nil
        }

        do {
            let transcriptionStartedAt = Date()
            let result = try await transcriptionService.stopRecording()
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStartedAt)

            stateStore.updateState { state in
                state.transcript = result.text
                state.session = .pasting
            }

            let insertionResult = try await insertionService.insert(result.text)

            stateStore.updateState { state in
                state.lastInsertionResult = insertionResult
                state.latencyMetrics = LatencyMetrics(
                    recordingDuration: result.recordingDuration,
                    transcriptionDuration: transcriptionDuration,
                    pasteDuration: insertionResult.pasteDuration,
                    totalDuration: result.recordingDuration + transcriptionDuration + insertionResult.pasteDuration,
                    modelLoadDuration: result.modelLoadDuration,
                    backendPipelineDuration: result.pipelineDuration
                )
                state.session = .idle
            }

            logger.info(
                "Completed transcription and insertion. record=\(result.recordingDuration, format: .fixed(precision: 2))s transcribe=\(transcriptionDuration, format: .fixed(precision: 2))s paste=\(insertionResult.pasteDuration, format: .fixed(precision: 2))s total=\((result.recordingDuration + transcriptionDuration + insertionResult.pasteDuration), format: .fixed(precision: 2))s"
            )
        } catch {
            present(error)
        }
    }

    private func clearFailureForNewAttempt() {
        stateStore?.updateState { state in
            state.latencyMetrics = nil

            if case .failed = state.session {
                state.session = .idle
            }
        }
    }

    private func present(_ error: Error) {
        let failure = CueFailure.from(error)

        stateStore?.updateState { state in
            state.session = .failed(failure)
        }

        logger.error("\(failure.message, privacy: .public)")
    }
}
