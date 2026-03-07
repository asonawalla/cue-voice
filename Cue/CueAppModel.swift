import AppKit
import Foundation
import Observation
import os

@MainActor
@Observable
final class CueAppModel {
    var phase: CuePhase = .idle
    var modelStatus: ModelPreparationStatus = .idle
    var permissionSnapshot = CuePermissionSnapshot(microphone: .notDetermined, paste: .notDetermined)
    var hasLoadedPermissionSnapshot = false
    var transcript = ""
    var errorMessage: String?
    var latencyMetrics: LatencyMetrics?
    var lastInsertionResult: CueInsertionResult?
    var setupWindowPresentationToken = 0
    private(set) var lastError: CueError?

    private let transcriptionService: TranscriptionService
    private let insertionService: TextInsertionService
    private let permissionService: PermissionService
    private let notificationCenter: NotificationCenter
    private let logger = Logger(subsystem: "dev.sonawalla.Cue", category: "AppModel")

    private var hasLaunched = false
    private var isPreparingModel = false
    private var didAttemptPastePermissionSetup = false
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

    var isSetupComplete: Bool {
        hasLoadedPermissionSnapshot && permissionSnapshot.isReadyForUse
    }

    var shouldShowSetupExperience: Bool {
        !hasLoadedPermissionSnapshot || !isSetupComplete
    }

    var shouldOfferModelRetry: Bool {
        isSetupComplete && !isModelReady && !isModelPreparing
    }

    var shouldOfferPastePermissionRecovery: Bool {
        if case .pastePermissionDenied = lastError {
            return true
        }

        return didAttemptPastePermissionSetup
    }

    var windowButtonTitle: String {
        isSetupComplete ? "Open Diagnostics" : "Open Setup"
    }

    var menuBarSymbolName: String {
        guard hasLoadedPermissionSnapshot else {
            return "waveform.circle"
        }

        guard isSetupComplete else {
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

        guard isSetupComplete else {
            return "Setup Required"
        }

        switch phase {
        case .idle:
            return isModelReady ? "Ready" : "Preparing Model"
        default:
            return phase.title
        }
    }

    var menuBarSecondaryStatus: String? {
        guard hasLoadedPermissionSnapshot else {
            return "Cue is checking which permissions are available."
        }

        guard isSetupComplete else {
            return permissionSnapshot.setupSummary
        }

        switch phase {
        case .recording:
            return "Release the shortcut to stop recording."
        case .transcribing:
            return "WhisperKit is transcribing the latest clip."
        case .pasting:
            return "Cue is pasting the latest transcript into the frontmost app."
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
        refreshPermissionSnapshot()

        guard isSetupComplete else {
            requestSetupWindowPresentation()
            return
        }

        await warmModel()
    }

    func refreshPermissions() async {
        refreshPermissionSnapshot()

        guard isSetupComplete else {
            return
        }

        await warmModel()
    }

    func requestMicrophonePermission() async {
        _ = await permissionService.requestMicrophonePermission()
        await refreshPermissions()
        requestSetupWindowPresentation()
    }

    func requestPastePermission() async {
        didAttemptPastePermissionSetup = true
        _ = await permissionService.requestPastePermission()
        await refreshPermissions()
        requestSetupWindowPresentation()
    }

    func openMicrophoneSettings() {
        permissionService.openSystemSettings(for: .microphone)
    }

    func openAccessibilitySettings() {
        didAttemptPastePermissionSetup = true
        permissionService.openSystemSettings(for: .paste)
    }

    func retryModelPreparation() async {
        await warmModel()
    }

    func handlePushToTalkPressed() async {
        guard phase != .recording, phase != .transcribing, phase != .pasting else {
            return
        }

        refreshPermissionSnapshot()

        guard isSetupComplete else {
            logger.info("Ignoring push-to-talk press because setup is incomplete")
            requestSetupWindowPresentation()
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

        guard isSetupComplete else {
            logger.info("Ignoring record start because setup is incomplete")
            requestSetupWindowPresentation()
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
                "Completed transcription and paste. record=\(result.recordingDuration, format: .fixed(precision: 2))s transcribe=\(transcriptionDuration, format: .fixed(precision: 2))s paste=\(insertionResult.pasteDuration, format: .fixed(precision: 2))s total=\((result.recordingDuration + transcriptionDuration + insertionResult.pasteDuration), format: .fixed(precision: 2))s"
            )
        } catch {
            present(error)
        }
    }

    func relaunchApplication() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { [logger] _, error in
            Task { @MainActor in
                if let error {
                    logger.error("Failed to relaunch Cue: \(error.localizedDescription, privacy: .public)")
                    self.present(CueError.pasteFailed("Cue could not relaunch itself. Quit and reopen it manually."))
                    return
                }

                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func handleApplicationDidBecomeActive() async {
        guard hasLaunched else {
            return
        }

        await refreshPermissions()
    }

    private func warmModel() async {
        guard isSetupComplete else {
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

    private func requestSetupWindowPresentation() {
        clearPermissionRelatedErrorIfNeeded()
        setupWindowPresentationToken += 1
    }

    private func refreshPermissionSnapshot() {
        permissionSnapshot = permissionService.currentPermissionSnapshot()
        hasLoadedPermissionSnapshot = true
        clearPermissionRelatedErrorIfNeeded()
    }

    private func clearPermissionRelatedErrorIfNeeded() {
        guard let lastError, lastError.isPermissionRelated else {
            return
        }

        guard !isSetupComplete else {
            return
        }

        self.lastError = nil
        errorMessage = nil

        if phase == .error {
            phase = .idle
        }
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

            if !isSetupComplete {
                requestSetupWindowPresentation()
            }
        }
    }
}
