import Foundation

@MainActor
protocol CueStateStore: AnyObject {
    var state: CueAppState { get set }
}

@MainActor
extension CueStateStore {
    func updateState(_ mutate: (inout CueAppState) -> Void) {
        var updatedState = state
        mutate(&updatedState)
        state = updatedState
    }
}

@MainActor
final class CueWorkflowCoordinator {
    private let setupCoordinator: CueSetupCoordinator
    private let dictationCoordinator: CueDictationCoordinator
    private var hasLaunched = false

    init(
        transcriptionService: TranscriptionService,
        insertionService: TextInsertionService,
        permissionService: PermissionService
    ) {
        setupCoordinator = CueSetupCoordinator(
            transcriptionService: transcriptionService,
            permissionService: permissionService
        )
        dictationCoordinator = CueDictationCoordinator(
            transcriptionService: transcriptionService,
            insertionService: insertionService
        )
    }

    var initialState: CueAppState {
        setupCoordinator.initialState()
    }

    func bind(to stateStore: any CueStateStore) {
        setupCoordinator.bind(to: stateStore)
        dictationCoordinator.bind(to: stateStore)
    }

    func launch() async {
        guard !hasLaunched else {
            return
        }

        hasLaunched = true
        setupCoordinator.refreshPermissions()
        await setupCoordinator.warmModel()
    }

    func refreshPermissions() async {
        setupCoordinator.refreshPermissions()
        await setupCoordinator.warmModel()
    }

    func requestMicrophonePermission() async {
        await setupCoordinator.requestMicrophonePermission()
    }

    func retryModelPreparation() async {
        await setupCoordinator.warmModel()
    }

    func openMicrophoneSettings() {
        setupCoordinator.openMicrophoneSettings()
    }

    func openInputMonitoringSettings() {
        setupCoordinator.openInputMonitoringSettings()
    }

    func openAccessibilitySettings() {
        setupCoordinator.openAccessibilitySettings()
    }

    func handlePushToTalkPressed() async {
        await dictationCoordinator.handlePushToTalkPressed(using: setupCoordinator)
    }

    func handlePushToTalkReleased() async {
        await dictationCoordinator.handlePushToTalkReleased()
    }

    func handleApplicationDidBecomeActive() async {
        guard hasLaunched else {
            return
        }

        await refreshPermissions()
    }
}
