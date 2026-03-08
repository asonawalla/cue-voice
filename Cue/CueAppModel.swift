import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class CueAppModel: CueStateStore {
    var state: CueAppState

    private let workflowCoordinator: CueWorkflowCoordinator
    private let notificationCenter: NotificationCenter

    private var activationObserver: NSObjectProtocol?

    init(
        transcriptionService: TranscriptionService? = nil,
        insertionService: TextInsertionService? = nil,
        permissionService: PermissionService? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        let transcriptionService = transcriptionService ?? WhisperKitTranscriptionService()
        let insertionService = insertionService ?? PasteboardInsertionService()
        let permissionService = permissionService ?? SystemPermissionService()

        self.workflowCoordinator = CueWorkflowCoordinator(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService
        )
        self.state = workflowCoordinator.initialState
        self.notificationCenter = notificationCenter

        workflowCoordinator.bind(to: self)

        activationObserver = notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.workflowCoordinator.handleApplicationDidBecomeActive()
            }
        }
    }

    var permissionSnapshot: CuePermissionSnapshot {
        state.setup.permissions
    }

    var hasLoadedPermissionSnapshot: Bool {
        state.setup.hasLoadedPermissions
    }

    var modelStatus: ModelPreparationStatus {
        state.setup.modelStatus
    }

    var transcript: String {
        state.transcript
    }

    var errorMessage: String? {
        state.currentFailure?.message
    }

    var latencyMetrics: LatencyMetrics? {
        state.latencyMetrics
    }

    var lastInsertionResult: CueInsertionResult? {
        state.lastInsertionResult
    }

    var presentation: CueAppPresentation {
        CueAppPresentation(state: state)
    }

    var isModelReady: Bool {
        state.isModelReady
    }

    var isModelPreparing: Bool {
        state.setup.modelStatus.isPreparing
    }

    var isReadyToRecord: Bool {
        state.isReadyToRecord
    }

    var needsPermissionPrompt: Bool {
        presentation.needsPermissionPrompt
    }

    var shouldOfferModelRetry: Bool {
        presentation.shouldOfferModelRetry
    }

    var automaticPasteWarningMessage: String? {
        presentation.setup.automaticPasteWarningMessage
    }

    var accessibilityRestartMessage: String? {
        presentation.setup.accessibilityRestartMessage
    }

    var showsAutomaticPasteIndicator: Bool {
        presentation.showsAutomaticPasteIndicator
    }

    var menuBarSymbolName: String {
        presentation.menuBarSymbolName
    }

    var menuBarPrimaryStatus: String {
        presentation.menuBarPrimaryStatus
    }

    var menuBarSecondaryStatus: String? {
        presentation.menuBarSecondaryStatus
    }

    var sessionState: CueSessionState {
        state.session
    }

    func launch() async {
        await workflowCoordinator.launch()
    }

    func refreshPermissions() async {
        await workflowCoordinator.refreshPermissions()
    }

    func requestMicrophonePermission() async {
        await workflowCoordinator.requestMicrophonePermission()
    }

    func openMicrophoneSettings() {
        workflowCoordinator.openMicrophoneSettings()
    }

    func openAccessibilitySettings() {
        workflowCoordinator.openAccessibilitySettings()
    }

    func restartApplication() {
        workflowCoordinator.restartApplication()
    }

    func retryModelPreparation() async {
        await workflowCoordinator.retryModelPreparation()
    }

    func handlePushToTalkPressed() async {
        await workflowCoordinator.handlePushToTalkPressed()
    }

    func handlePushToTalkReleased() async {
        await workflowCoordinator.handlePushToTalkReleased()
    }

    func perform(_ action: CueAppAction, openMainWindow: (() -> Void)? = nil) {
        switch action {
        case .requestMicrophonePermission:
            Task {
                await requestMicrophonePermission()
            }
        case .openMicrophoneSettings:
            openMicrophoneSettings()
        case .openAccessibilitySettings:
            openAccessibilitySettings()
        case .restartApplication:
            restartApplication()
        case .retryModelPreparation:
            Task {
                await retryModelPreparation()
            }
        case .openMainWindow:
            openMainWindow?()
            NSApplication.shared.activate(ignoringOtherApps: true)
        case .quit:
            NSApplication.shared.terminate(nil)
        }
    }
}
