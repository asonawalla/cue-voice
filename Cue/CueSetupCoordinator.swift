import Foundation
import os

@MainActor
final class CueSetupCoordinator {
    private weak var stateStore: (any CueStateStore)?

    private let transcriptionService: TranscriptionService
    private let permissionService: PermissionService
    private let logger = Logger(subsystem: "dev.sonawalla.Cue", category: "Setup")

    private var isPreparingModel = false
    private var isRunningPermissionBootstrap = false

    init(
        transcriptionService: TranscriptionService,
        permissionService: PermissionService
    ) {
        self.transcriptionService = transcriptionService
        self.permissionService = permissionService

        self.transcriptionService.statusHandler = { [weak self] status in
            self?.stateStore?.updateState { state in
                state.setup.modelStatus = status
            }
        }
    }

    func bind(to stateStore: any CueStateStore) {
        self.stateStore = stateStore
    }

    func initialState() -> CueAppState {
        CueAppState.initial(permissionSnapshot: permissionService.currentPermissionSnapshot())
    }

    func refreshPermissions() {
        let snapshot = permissionService.currentPermissionSnapshot()

        stateStore?.updateState { state in
            state.setup.permissions = snapshot
            state.setup.hasLoadedPermissions = true

            if snapshot.isMicrophoneReady, state.currentFailure?.isPermissionRelated == true {
                state.session = .idle
            }
        }
    }

    func requestMicrophonePermission() async {
        let result = await permissionService.requestMicrophonePermission()
        refreshPermissions()

        guard result.isGranted else {
            present(CueError.microphonePermissionDenied)
            return
        }

        await warmModel()
    }

    func openMicrophoneSettings() {
        permissionService.openSystemSettings(for: .microphone)
    }

    func openAccessibilitySettings() {
        permissionService.requestAccessibilityPermission()
        permissionService.openSystemSettings(for: .accessibility)
    }

    func restartApplication() {
        permissionService.restartApplication()
    }

    func runFirstUsePermissionBootstrap() async {
        guard !isRunningPermissionBootstrap else {
            return
        }

        isRunningPermissionBootstrap = true
        logger.info("Running first-use permission bootstrap")

        defer {
            isRunningPermissionBootstrap = false
        }

        let microphoneState = await permissionService.requestMicrophonePermission()
        refreshPermissions()

        guard microphoneState.isGranted else {
            present(CueError.microphonePermissionDenied)
            return
        }

        await warmModel()
    }

    func warmModel() async {
        guard let stateStore else {
            return
        }

        guard stateStore.state.setup.permissions.isMicrophoneReady else {
            return
        }

        guard !isPreparingModel else {
            return
        }

        guard !stateStore.state.isModelReady else {
            if stateStore.state.currentFailure?.cueError?.isModelPreparationRelated == true {
                stateStore.updateState { state in
                    state.session = .idle
                }
            }
            return
        }

        isPreparingModel = true

        defer {
            isPreparingModel = false
        }

        do {
            try await transcriptionService.prepareModel()

            stateStore.updateState { state in
                if state.currentFailure?.cueError?.isModelPreparationRelated == true {
                    state.session = .idle
                }
            }
        } catch {
            present(error)
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
