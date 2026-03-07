import AppKit
import Foundation
import Observation
import os

@MainActor
@Observable
final class CueAppModel {
    var phase: CuePhase = .idle
    var modelStatus: ModelPreparationStatus = .idle
    var permissionSnapshot = CuePermissionSnapshot(microphone: .notDetermined, paste: .unavailable)
    var hasLoadedPermissionSnapshot = false
    var transcript = ""
    var errorMessage: String?
    var latencyMetrics: LatencyMetrics?
    var lastInsertionResult: CueInsertionResult?
    private(set) var lastError: CueError?

    private let transcriptionService: TranscriptionService
    private let insertionService: TextInsertionService
    private let permissionService: PermissionService
    private let notificationCenter: NotificationCenter
    private let logger = Logger(subsystem: "dev.sonawalla.Cue", category: "AppModel")

    private var hasLaunched = false
    private var isPreparingModel = false
    private var isRunningPermissionBootstrap = false
    private var activationObserver: NSObjectProtocol?

    init(
        transcriptionService: TranscriptionService? = nil,
        insertionService: TextInsertionService? = nil,
        permissionService: PermissionService? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.transcriptionService = transcriptionService ?? WhisperKitTranscriptionService()
        self.insertionService = insertionService ?? PasteboardInsertionService()
        self.permissionService = permissionService ?? SystemPermissionService()
        self.notificationCenter = notificationCenter

        self.transcriptionService.statusHandler = { [weak self] status in
            self?.modelStatus = status
        }

        activationObserver = notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleApplicationDidBecomeActive()
            }
        }
    }

    var isTranscribing: Bool {
        phase == .transcribing
    }

    var isPasting: Bool {
        phase == .pasting
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

    var isReadyToRecord: Bool {
        hasLoadedPermissionSnapshot && permissionSnapshot.isMicrophoneReady
    }

    var shouldOfferModelRetry: Bool {
        isReadyToRecord && !isModelReady && !isModelPreparing
    }

    var automaticPasteWarningMessage: String? {
        guard hasLoadedPermissionSnapshot else {
            return nil
        }

        guard permissionSnapshot.isMicrophoneReady else {
            return nil
        }

        guard !permissionSnapshot.canAutoPaste else {
            return nil
        }

        return "Automatic paste is off. Cue will copy transcripts to the clipboard until Accessibility is enabled."
    }

    var showsAutomaticPasteIndicator: Bool {
        hasLoadedPermissionSnapshot && permissionSnapshot.isMicrophoneReady && !permissionSnapshot.canAutoPaste
    }

    var menuBarSymbolName: String {
        guard hasLoadedPermissionSnapshot else {
            return "waveform.circle"
        }

        guard isReadyToRecord else {
            return "waveform.badge.exclamationmark"
        }

        switch phase {
        case .recording:
            return "waveform.circle.fill"
        case .transcribing:
            return "waveform.badge.magnifyingglass"
        case .pasting:
            return "waveform.badge.plus"
        case .error:
            return "waveform.badge.exclamationmark"
        case .idle:
            return isModelReady ? "waveform" : "waveform.circle"
        }
    }

    var menuBarPrimaryStatus: String {
        guard hasLoadedPermissionSnapshot else {
            return "Checking Permissions"
        }

        guard permissionSnapshot.isMicrophoneReady else {
            return "Microphone Required"
        }

        switch phase {
        case .idle:
            guard isModelReady else {
                return "Preparing Model"
            }

            return permissionSnapshot.canAutoPaste ? "Ready" : "Clipboard Mode"
        default:
            return phase.title
        }
    }

    var menuBarSecondaryStatus: String? {
        guard hasLoadedPermissionSnapshot else {
            return "Cue is checking which permissions are available."
        }

        guard permissionSnapshot.isMicrophoneReady else {
            return permissionSnapshot.setupSummary
        }

        switch phase {
        case .recording:
            return "Release the shortcut to stop recording."
        case .transcribing:
            return "WhisperKit is transcribing the latest clip."
        case .pasting:
            return "Cue is sending the latest transcript to the frontmost app."
        case .error:
            return errorMessage
        case .idle:
            guard isModelReady else {
                return modelStatus.title
            }

            return automaticPasteWarningMessage ?? "Hold the push-to-talk shortcut in any app."
        }
    }

    func launch() async {
        guard !hasLaunched else {
            return
        }

        hasLaunched = true
        refreshPermissionSnapshot()

        if permissionSnapshot.isMicrophoneReady {
            await warmModel()
        }
    }

    func refreshPermissions() async {
        refreshPermissionSnapshot()

        guard permissionSnapshot.isMicrophoneReady else {
            return
        }

        await warmModel()
    }

    func requestMicrophonePermission() async {
        let result = await permissionService.requestMicrophonePermission()
        refreshPermissionSnapshot()

        if !result.isGranted {
            present(CueError.microphonePermissionDenied)
            return
        }

        await requestAutomaticPastePermissionIfNeeded()
        await warmModel()
    }

    func requestPastePermission() async {
        _ = await permissionService.requestPastePermission()
        refreshPermissionSnapshot()
    }

    func openMicrophoneSettings() {
        permissionService.openSystemSettings(for: .microphone)
    }

    func openAccessibilitySettings() {
        permissionService.openSystemSettings(for: .paste)
    }

    func retryModelPreparation() async {
        await warmModel()
    }

    func handlePushToTalkPressed() async {
        guard phase != .recording, phase != .transcribing, phase != .pasting, !isRunningPermissionBootstrap else {
            return
        }

        refreshPermissionSnapshot()

        if permissionSnapshot.microphone == .notDetermined {
            await runFirstUsePermissionBootstrap()
            return
        }

        guard permissionSnapshot.isMicrophoneReady else {
            logger.info("Ignoring push-to-talk press because microphone access is unavailable")
            present(CueError.microphonePermissionDenied)
            return
        }

        guard isModelReady else {
            logger.info("Ignoring push-to-talk press while model status is \(self.modelStatus.title, privacy: .public)")

            if !isModelPreparing {
                await warmModel()
            }

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

        guard !isTranscribing, !isPasting else {
            logger.info("Ignoring record start while Cue is still transcribing or pasting")
            return
        }

        refreshPermissionSnapshot()

        guard permissionSnapshot.isMicrophoneReady else {
            logger.info("Ignoring record start because microphone access is unavailable")
            present(CueError.microphonePermissionDenied)
            return
        }

        guard isModelReady else {
            logger.info("Ignoring record start because the model is not ready")

            if !isModelPreparing {
                await warmModel()
            }

            return
        }

        errorMessage = nil
        lastError = nil
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
        lastError = nil
        latencyMetrics = nil

        do {
            let transcriptionStartedAt = Date()
            let result = try await transcriptionService.stopRecording()
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStartedAt)

            transcript = result.text
            phase = .pasting

            let insertionResult = try await insertionService.insert(result.text)
            lastInsertionResult = insertionResult
            latencyMetrics = LatencyMetrics(
                recordingDuration: result.recordingDuration,
                transcriptionDuration: transcriptionDuration,
                pasteDuration: insertionResult.pasteDuration,
                totalDuration: result.recordingDuration + transcriptionDuration + insertionResult.pasteDuration,
                modelLoadDuration: result.modelLoadDuration,
                backendPipelineDuration: result.pipelineDuration
            )
            phase = .idle

            logger.info(
                "Completed transcription and insertion. record=\(result.recordingDuration, format: .fixed(precision: 2))s transcribe=\(transcriptionDuration, format: .fixed(precision: 2))s paste=\(insertionResult.pasteDuration, format: .fixed(precision: 2))s total=\((result.recordingDuration + transcriptionDuration + insertionResult.pasteDuration), format: .fixed(precision: 2))s"
            )
        } catch {
            present(error)
        }
    }

    private func handleApplicationDidBecomeActive() async {
        guard hasLaunched else {
            return
        }

        await refreshPermissions()
    }

    private func warmModel() async {
        guard permissionSnapshot.isMicrophoneReady else {
            return
        }

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
            lastError = nil

            if phase == .error {
                phase = .idle
            }
        } catch {
            present(error)
        }
    }

    private func refreshPermissionSnapshot() {
        permissionSnapshot = permissionService.currentPermissionSnapshot()
        hasLoadedPermissionSnapshot = true

        if permissionSnapshot.isMicrophoneReady {
            if lastError == .microphonePermissionDenied {
                lastError = nil
                errorMessage = nil

                if phase == .error {
                    phase = .idle
                }
            }
        }
    }

    private func runFirstUsePermissionBootstrap() async {
        guard !isRunningPermissionBootstrap else {
            return
        }

        isRunningPermissionBootstrap = true
        logger.info("Running first-use permission bootstrap")

        defer {
            isRunningPermissionBootstrap = false
        }

        let microphoneState = await permissionService.requestMicrophonePermission()
        refreshPermissionSnapshot()

        guard microphoneState.isGranted else {
            present(CueError.microphonePermissionDenied)
            return
        }

        await requestAutomaticPastePermissionIfNeeded()
        await warmModel()
    }

    private func requestAutomaticPastePermissionIfNeeded() async {
        guard permissionSnapshot.isMicrophoneReady else {
            return
        }

        guard !permissionSnapshot.canAutoPaste else {
            return
        }

        logger.info("Requesting automatic paste access after microphone grant")
        _ = await permissionService.requestPastePermission()
        refreshPermissionSnapshot()
    }

    private func present(_ error: Error) {
        let message: String

        if let cueError = error as? CueError {
            lastError = cueError
        } else {
            lastError = nil
        }

        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            message = description
        } else {
            message = error.localizedDescription
        }

        errorMessage = message
        phase = .error
        logger.error("\(message, privacy: .public)")

        if let cueError = lastError, cueError.isPermissionRelated {
            refreshPermissionSnapshot()
        }
    }
}
