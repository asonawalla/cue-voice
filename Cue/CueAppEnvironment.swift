import AppKit
import Foundation

struct CueAppEnvironment {
    let model: CueAppModel
    let triggerManager: CueTriggerManager

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(CueAppConfiguration.uiTestingLaunchArgument)
    }

    @MainActor
    static func make() -> CueAppEnvironment {
        if isUITesting {
            NSApplication.shared.setActivationPolicy(.regular)

            let model = CueAppModel(
                transcriptionService: UITestTranscriptionService(),
                insertionService: UITestTextInsertionService(),
                permissionService: UITestPermissionService()
            )
            let triggerManager = CueTriggerManager(
                appModel: model,
                bindingService: DisabledPushToTalkBindingService()
            )

            return CueAppEnvironment(model: model, triggerManager: triggerManager)
        }

        let model = CueAppModel()
        let triggerManager = CueTriggerManager(appModel: model)
        return CueAppEnvironment(model: model, triggerManager: triggerManager)
    }
}

@MainActor
private final class UITestPermissionService: PermissionService {
    private var snapshot = CuePermissionSnapshot(microphone: .granted, inputMonitoring: .granted, accessibility: .granted)

    func currentPermissionSnapshot() -> CuePermissionSnapshot {
        snapshot
    }

    func requestMicrophonePermission() async -> CuePermissionState {
        snapshot = CuePermissionSnapshot(
            microphone: .granted,
            inputMonitoring: snapshot.inputMonitoring,
            accessibility: snapshot.accessibility
        )
        return .granted
    }

    func requestInputMonitoringPermission() {
        snapshot = CuePermissionSnapshot(
            microphone: snapshot.microphone,
            inputMonitoring: .granted,
            accessibility: snapshot.accessibility
        )
    }

    func requestAccessibilityPermission() {
        snapshot = CuePermissionSnapshot(
            microphone: snapshot.microphone,
            inputMonitoring: snapshot.inputMonitoring,
            accessibility: .granted
        )
    }

    func openSystemSettings(for permission: CuePermissionKind) {
        _ = permission
    }
}

@MainActor
private final class UITestTranscriptionService: TranscriptionService {
    var statusHandler: ((ModelPreparationStatus) -> Void)?

    func prepareModel() async throws {
        statusHandler?(.ready)
    }

    func startRecording() async throws {}

    func stopRecording() async throws -> CueTranscriptionResult {
        CueTranscriptionResult(
            text: "UI test transcript",
            language: "en",
            recordingDuration: 1.2,
            modelLoadDuration: 0.1,
            pipelineDuration: 0.2
        )
    }
}

@MainActor
private final class UITestTextInsertionService: TextInsertionService {
    func insert(_ text: String) async throws -> CueInsertionResult {
        CueInsertionResult(
            delivery: .pasteCommandSent,
            targetAppName: "Notes",
            targetBundleIdentifier: "com.apple.Notes",
            pasteDuration: 0.05
        )
    }
}
