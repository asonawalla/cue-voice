import Foundation
import os

@MainActor
final class CueDictationCoordinator {
    private weak var stateStore: (any CueStateStore)?

    private let transcriptionService: TranscriptionService
    private let insertionService: TextInsertionService
    private let soundService: any SoundService
    private let logger = Logger(subsystem: "dev.sonawalla.Cue", category: "Dictation")

    private var currentRun: DictationRunTiming?

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
            logger.info("Ignoring push-to-talk press while model status is \(CueCopy.modelPreparationStatusTitle(state.setup.modelStatus), privacy: .public)")
            await setupCoordinator.warmModel()
            return
        }

        currentRun = DictationRunTiming(pressedAt: Date())
        await startRecording()
    }

    func handlePushToTalkReleased() async {
        currentRun?.releasedAt = Date()

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
        currentRun?.ackAt = Date()
        soundService.playRecordingStarted()

        do {
            try await transcriptionService.startRecording()

            stateStore.apply(.recordingStarted)
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

        currentRun?.proofOfLifeAt = Date()
        soundService.playRecordingStopped()

        stateStore.apply(.transcriptionStarted)

        do {
            let transcriptionStartedAt = Date()
            let result = try await transcriptionService.stopRecording()
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStartedAt)

            stateStore.apply(.transcriptionCompleted(result))

            let insertionResult = try await insertionService.insert(result.text)

            let run = currentRun
            let releaseToInsert = run?.releasedAt.map {
                insertionResult.pasteCommandPostedAt.timeIntervalSince($0)
            } ?? 0
            let metrics = LatencyMetrics(
                recordingDuration: result.recordingDuration,
                transcriptionDuration: transcriptionDuration,
                pasteDuration: insertionResult.pasteDuration,
                totalDuration: result.recordingDuration + transcriptionDuration + insertionResult.pasteDuration,
                modelLoadDuration: result.modelLoadDuration,
                backendPipelineDuration: result.pipelineDuration,
                pressToAck: run?.pressToAck ?? 0,
                releaseToProofOfLife: run?.releaseToProofOfLife ?? 0,
                releaseToInsert: releaseToInsert
            )

            stateStore.apply(.insertionCompleted(insertionResult, metrics))

            logger.info(
                "Completed transcription and insertion. press_to_ack=\((run?.pressToAck ?? 0) * 1000, format: .fixed(precision: 0))ms release_to_life=\((run?.releaseToProofOfLife ?? 0) * 1000, format: .fixed(precision: 0))ms release_to_insert=\(releaseToInsert * 1000, format: .fixed(precision: 0))ms | record=\(result.recordingDuration, format: .fixed(precision: 2))s transcribe=\(transcriptionDuration, format: .fixed(precision: 2))s paste=\(insertionResult.pasteDuration, format: .fixed(precision: 2))s"
            )
        } catch {
            present(error)
        }
    }

    private func clearFailureForNewAttempt() {
        stateStore?.apply(.dictationAttemptStarted)
    }

    private func present(_ error: Error) {
        let failure = CueFailure.from(error)

        if failure.cueError?.shouldPlayErrorSound == true {
            soundService.playError()
        }

        stateStore?.apply(.failurePresented(failure))

        logger.error("\(CueCopy.failureMessage(failure), privacy: .public)")
    }
}

private struct DictationRunTiming {
    let pressedAt: Date
    var ackAt: Date?
    var releasedAt: Date?
    var proofOfLifeAt: Date?

    var pressToAck: TimeInterval {
        ackAt.map { $0.timeIntervalSince(pressedAt) } ?? 0
    }

    var releaseToProofOfLife: TimeInterval {
        guard let releasedAt, let proofOfLifeAt else { return 0 }
        return proofOfLifeAt.timeIntervalSince(releasedAt)
    }
}
