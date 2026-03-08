import Foundation
@testable import Cue

@MainActor
final class FakeTranscriptionService: TranscriptionService {
    var statusHandler: ((ModelPreparationStatus) -> Void)?

    var prepareCallCount = 0
    var startRecordingCallCount = 0
    var stopRecordingCallCount = 0
    var prepareError: Error?
    var stopRecordingError: Error?
    var result = CueTranscriptionResult(
        text: "milestone transcript",
        language: "en",
        recordingDuration: 1.5,
        modelLoadDuration: 0.25,
        pipelineDuration: 0.5
    )

    func prepareModel() async throws {
        prepareCallCount += 1

        if let prepareError {
            throw prepareError
        }

        statusHandler?(.ready)
    }

    func startRecording() async throws {
        startRecordingCallCount += 1
    }

    func stopRecording() async throws -> CueTranscriptionResult {
        stopRecordingCallCount += 1

        if let stopRecordingError {
            throw stopRecordingError
        }

        return result
    }
}

@MainActor
final class FakeTextInsertionService: TextInsertionService {
    var insertCallCount = 0
    var insertError: Error?
    var result = CueInsertionResult(
        delivery: .pasteCommandSent,
        targetAppName: "TextEdit",
        targetBundleIdentifier: "com.apple.TextEdit",
        pasteDuration: 0.12
    )

    func insert(_ text: String) async throws -> CueInsertionResult {
        insertCallCount += 1

        if let insertError {
            throw insertError
        }

        return result
    }
}

@MainActor
final class FakePermissionService: PermissionService {
    var snapshot: CuePermissionSnapshot
    var currentSnapshotCallCount = 0
    var requestMicrophoneCallCount = 0
    var requestInputMonitoringCallCount = 0
    var requestAccessibilityCallCount = 0
    var openedSettingsPermissions: [CuePermissionKind] = []
    var microphoneRequestResult: CuePermissionState?

    init(snapshot: CuePermissionSnapshot = CuePermissionSnapshot(microphone: .granted, inputMonitoring: .granted, accessibility: .granted)) {
        self.snapshot = snapshot
    }

    func currentPermissionSnapshot() -> CuePermissionSnapshot {
        currentSnapshotCallCount += 1
        return snapshot
    }

    func requestMicrophonePermission() async -> CuePermissionState {
        requestMicrophoneCallCount += 1

        if let microphoneRequestResult {
            snapshot = CuePermissionSnapshot(
                microphone: microphoneRequestResult,
                inputMonitoring: snapshot.inputMonitoring,
                accessibility: snapshot.accessibility
            )
        }

        return snapshot.microphone
    }

    func requestInputMonitoringPermission() {
        requestInputMonitoringCallCount += 1
    }

    func requestAccessibilityPermission() {
        requestAccessibilityCallCount += 1
    }

    func openSystemSettings(for permission: CuePermissionKind) {
        openedSettingsPermissions.append(permission)
    }
}

@MainActor
final class FakePushToTalkBindingService: PushToTalkBindingService {
    var modifier: PushToTalkModifier
    var setModifierCalls: [PushToTalkModifier] = []
    var refreshMonitoringCallCount = 0

    private(set) var onPress: (() -> Void)?
    private(set) var onRelease: (() -> Void)?

    init(modifier: PushToTalkModifier = .function) {
        self.modifier = modifier
    }

    func currentModifier() -> PushToTalkModifier {
        modifier
    }

    func setModifier(_ modifier: PushToTalkModifier) {
        self.modifier = modifier
        setModifierCalls.append(modifier)
    }

    func startMonitoring(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
    }

    func refreshMonitoring() {
        refreshMonitoringCallCount += 1
    }
}
