import AppKit
import Foundation
import Observation
import os

@MainActor
@Observable
final class CueAppModel {
    private(set) var state: CueAppState
    var debugCapturesEnabled: Bool {
        didSet {
            defaults.set(debugCapturesEnabled, forKey: CueAppConfiguration.debugCapturesEnabledDefaultsKey)
        }
    }

    private let transcriptionService: TranscriptionService
    private let insertionService: TextInsertionService
    private let permissionService: PermissionService
    private let soundService: any SoundService
    private let defaults: UserDefaults
    private let setupLogger = Logger(subsystem: "dev.sonawalla.Cue", category: "Setup")
    private let dictationLogger = Logger(subsystem: "dev.sonawalla.Cue", category: "Dictation")

    private var activationObserver: NSObjectProtocol?
    private var hasLaunched = false
    private var isPreparingModel = false
    private var isRequestingMicrophonePermission = false
    private var isPushToTalkHeld = false
    private var currentRun: DictationRunTiming?

    init(
        transcriptionService: TranscriptionService? = nil,
        insertionService: TextInsertionService? = nil,
        permissionService: PermissionService? = nil,
        soundService: (any SoundService)? = nil,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        let transcriptionService = transcriptionService ?? WhisperKitTranscriptionService(defaults: defaults)
        let permissionService = permissionService ?? SystemPermissionService()

        self.transcriptionService = transcriptionService
        self.insertionService = insertionService ?? PasteboardInsertionService()
        self.permissionService = permissionService
        self.soundService = soundService ?? SystemSoundService()
        self.defaults = defaults
        self.state = CueAppState(permissions: permissionService.currentPermissionSnapshot())
        self.debugCapturesEnabled = defaults.bool(
            forKey: CueAppConfiguration.debugCapturesEnabledDefaultsKey
        )

        transcriptionService.statusHandler = { [weak self] status in
            self?.state.modelStatus = status
        }

        activationObserver = notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.hasLaunched else {
                    return
                }

                await self.refreshPermissions()
            }
        }
    }

    var presentation: CueAppPresentation {
        CueAppPresentation(state: state)
    }

    func launch() async {
        guard !hasLaunched else {
            return
        }

        hasLaunched = true
        refreshPermissionSnapshot()
        await warmModel()
    }

    func refreshPermissions() async {
        refreshPermissionSnapshot()
        await warmModel()
    }

    func requestMicrophonePermission() async {
        guard !isRequestingMicrophonePermission else {
            return
        }

        isRequestingMicrophonePermission = true
        defer {
            isRequestingMicrophonePermission = false
        }

        await permissionService.requestMicrophonePermission()
        refreshPermissionSnapshot()

        guard state.permissions.isMicrophoneReady else {
            present(CueError.microphonePermissionDenied, logger: setupLogger)
            return
        }

        await warmModel()
    }

    func openAccessibilitySettings() {
        permissionService.requestAccessibilityPermission()
        permissionService.openSystemSettings(for: .accessibility)
    }

    func handlePushToTalkPressed() {
        guard currentRun == nil, !state.session.isBusy else {
            return
        }

        refreshPermissionSnapshot()

        if state.permissions.microphone == .notDetermined {
            setupLogger.info("Running first-use permission bootstrap")
            Task {
                await requestMicrophonePermission()
            }
            return
        }

        guard state.permissions.isMicrophoneReady else {
            dictationLogger.info("Ignoring push-to-talk press because microphone access is unavailable")
            present(CueError.microphonePermissionDenied, logger: dictationLogger)
            return
        }

        guard state.permissions.isAccessibilityReady else {
            dictationLogger.info("Ignoring push-to-talk press because accessibility access is unavailable")
            present(CueError.accessibilityPermissionDenied, logger: dictationLogger)
            return
        }

        guard state.modelStatus.isReady else {
            dictationLogger.info(
                "Ignoring push-to-talk press while model status is \(CueCopy.modelPreparationStatusTitle(self.state.modelStatus), privacy: .public)"
            )
            Task {
                await warmModel()
            }
            return
        }

        isPushToTalkHeld = true
        currentRun = DictationRunTiming(pressedAt: Date())
        clearFailureForNewAttempt()
        currentRun?.ackAt = Date()
        soundService.playRecordingStarted()

        Task {
            await startRecording()
        }
    }

    func handlePushToTalkReleased() {
        isPushToTalkHeld = false
        if currentRun?.releasedAt == nil {
            currentRun?.releasedAt = Date()
        }

        guard state.session == .recording else {
            return
        }

        Task {
            await stopRecording()
        }
    }

    private func startRecording() async {
        do {
            try await transcriptionService.startRecording()
            state.session = .recording

            if !isPushToTalkHeld {
                await stopRecording()
            }
        } catch {
            currentRun = nil
            present(error, logger: dictationLogger)
        }
    }

    func openDebugCapturesFolder() {
        let directoryURL = CueAppConfiguration.debugCaptureRootDirectory()
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directoryURL)
    }

    func clearDebugCaptures() {
        let directoryURL = CueAppConfiguration.debugCaptureRootDirectory()
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return
        }

        try? FileManager.default.removeItem(at: directoryURL)
    }

    func perform(_ action: CueAppAction) {
        switch action {
        case .requestMicrophonePermission:
            Task {
                await requestMicrophonePermission()
            }
        case .requestAccessibilityPermission:
            permissionService.requestAccessibilityPermission()
        case .openMicrophoneSettings:
            permissionService.openSystemSettings(for: .microphone)
        case .openAccessibilitySettings:
            openAccessibilitySettings()
        case .retryModelPreparation:
            Task {
                await warmModel()
            }
        }
    }

    private func refreshPermissionSnapshot() {
        let snapshot = permissionService.currentPermissionSnapshot()
        state.permissions = snapshot

        if let cueError = state.currentFailure?.cueError, snapshot.resolves(cueError) {
            state.session = .idle
        }
    }

    private func warmModel() async {
        guard state.permissions.isFullyConfigured, !isPreparingModel else {
            return
        }

        guard !state.modelStatus.isReady else {
            if state.currentFailure?.cueError?.isModelPreparationRelated == true {
                state.session = .idle
            }
            return
        }

        isPreparingModel = true
        defer {
            isPreparingModel = false
        }

        do {
            try await transcriptionService.prepareModel()

            if state.currentFailure?.cueError?.isModelPreparationRelated == true {
                state.session = .idle
            }
        } catch {
            present(error, logger: setupLogger)
        }
    }

    private func stopRecording() async {
        guard state.session == .recording else {
            return
        }

        currentRun?.proofOfLifeAt = Date()
        soundService.playRecordingStopped()
        state.session = .transcribing
        state.latencyMetrics = nil

        do {
            let transcriptionStartedAt = Date()
            let transcript = try await transcriptionService.stopRecording()
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStartedAt)

            state.session = .pasting
            let insertionResult = try await insertionService.insert(transcript)

            let run = currentRun
            let releaseToInsert = run?.releasedAt.map {
                insertionResult.pasteCommandPostedAt.timeIntervalSince($0)
            } ?? 0
            let metrics = LatencyMetrics(
                transcriptionDuration: transcriptionDuration,
                pasteDuration: insertionResult.pasteDuration,
                pressToAck: run?.pressToAck ?? 0,
                releaseToProofOfLife: run?.releaseToProofOfLife ?? 0,
                releaseToInsert: releaseToInsert
            )

            state.latencyMetrics = metrics
            state.session = .idle
            currentRun = nil

            dictationLogger.info(
                "Completed transcription and insertion. press_to_ack=\((run?.pressToAck ?? 0) * 1000, format: .fixed(precision: 0))ms release_to_life=\((run?.releaseToProofOfLife ?? 0) * 1000, format: .fixed(precision: 0))ms release_to_insert=\(releaseToInsert * 1000, format: .fixed(precision: 0))ms | transcribe=\(transcriptionDuration, format: .fixed(precision: 2))s paste=\(insertionResult.pasteDuration, format: .fixed(precision: 2))s"
            )
        } catch {
            currentRun = nil
            present(error, logger: dictationLogger)
        }
    }

    private func clearFailureForNewAttempt() {
        state.latencyMetrics = nil

        if case .failed = state.session {
            state.session = .idle
        }
    }

    private func present(_ error: Error, logger: Logger) {
        let failure = CueFailure.from(error)

        if failure.cueError?.shouldPlayErrorSound == true {
            soundService.playError()
        }

        state.session = .failed(failure)
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
        guard let releasedAt, let proofOfLifeAt else {
            return 0
        }

        return proofOfLifeAt.timeIntervalSince(releasedAt)
    }
}
