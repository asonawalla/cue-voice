import AppKit
import Foundation
import Observation

protocol WorkspaceOpening {
    @discardableResult
    func open(_ url: URL) -> Bool
}

extension NSWorkspace: WorkspaceOpening {}

@MainActor
@Observable
final class CueAppModel: CueStateStore {
    var state: CueAppState
    var debugCapturesEnabled: Bool {
        didSet {
            defaults.set(debugCapturesEnabled, forKey: CueAppConfiguration.debugCapturesEnabledDefaultsKey)
        }
    }

    private let workflowCoordinator: CueWorkflowCoordinator
    private let notificationCenter: NotificationCenter
    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let workspace: any WorkspaceOpening

    private var activationObserver: NSObjectProtocol?

    init(
        transcriptionService: TranscriptionService? = nil,
        insertionService: TextInsertionService? = nil,
        permissionService: PermissionService? = nil,
        soundService: (any SoundService)? = nil,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        workspace: any WorkspaceOpening = NSWorkspace.shared,
        notificationCenter: NotificationCenter = .default
    ) {
        let transcriptionService = transcriptionService ?? WhisperKitTranscriptionService(
            fileManager: fileManager,
            defaults: defaults
        )
        let insertionService = insertionService ?? PasteboardInsertionService()
        let permissionService = permissionService ?? SystemPermissionService()
        let soundService = soundService ?? SystemSoundService()

        self.defaults = defaults
        self.fileManager = fileManager
        self.workspace = workspace
        debugCapturesEnabled = defaults.bool(forKey: CueAppConfiguration.debugCapturesEnabledDefaultsKey)
        self.workflowCoordinator = CueWorkflowCoordinator(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            soundService: soundService
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

    var debugCapturesLocationSummary: String {
        CueAppConfiguration.debugCaptureDisplayPath(fileManager: fileManager)
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

    func requestAccessibilityPermission() {
        workflowCoordinator.requestAccessibilityPermission()
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

    func openDebugCapturesFolder() {
        let directoryURL = CueAppConfiguration.debugCaptureRootDirectory(fileManager: fileManager)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        _ = workspace.open(directoryURL)
    }

    func clearDebugCaptures() {
        let directoryURL = CueAppConfiguration.debugCaptureRootDirectory(fileManager: fileManager)
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }

        try? fileManager.removeItem(at: directoryURL)
    }

    func perform(_ action: CueAppAction) {
        switch action {
        case .requestMicrophonePermission:
            Task {
                await requestMicrophonePermission()
            }
        case .requestAccessibilityPermission:
            requestAccessibilityPermission()
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
        case .quit:
            NSApplication.shared.terminate(nil)
        }
    }
}
