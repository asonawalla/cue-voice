import Foundation
@testable import Cue

@MainActor
final class FakeTranscriptionService: TranscriptionService {
    var statusHandler: ((ModelPreparationStatus) -> Void)?

    var prepareCallCount = 0
    var startRecordingCallCount = 0
    var stopRecordingCallCount = 0
    var prepareError: Error?
    var startRecordingError: Error?
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

        if let startRecordingError {
            throw startRecordingError
        }
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
    var requestAccessibilityCallCount = 0
    var restartApplicationCallCount = 0
    var openedSettingsPermissions: [CuePermissionKind] = []
    var microphoneRequestResult: CuePermissionState?

    init(snapshot: CuePermissionSnapshot = CuePermissionSnapshot(microphone: .granted, accessibility: .granted)) {
        self.snapshot = snapshot
    }

    func currentPermissionSnapshot() -> CuePermissionSnapshot {
        currentSnapshotCallCount += 1
        return snapshot
    }

    func requestMicrophonePermission() async -> CuePermissionState {
        requestMicrophoneCallCount += 1

        if let microphoneRequestResult {
            snapshot = CuePermissionSnapshot(microphone: microphoneRequestResult, accessibility: snapshot.accessibility)
        }

        return snapshot.microphone
    }

    func requestAccessibilityPermission() {
        requestAccessibilityCallCount += 1
    }

    func openSystemSettings(for permission: CuePermissionKind) {
        openedSettingsPermissions.append(permission)
    }

    func restartApplication() {
        restartApplicationCallCount += 1
    }
}

@MainActor
final class FakeSoundService: SoundService {
    var playRecordingStartedCallCount = 0
    var playRecordingStoppedCallCount = 0
    var playErrorCallCount = 0

    func playRecordingStarted() {
        playRecordingStartedCallCount += 1
    }

    func playRecordingStopped() {
        playRecordingStoppedCallCount += 1
    }

    func playError() {
        playErrorCallCount += 1
    }
}

@MainActor
final class FakePlayableSound: PlayableSound {
    var playCallCount = 0
    var stopCallCount = 0

    @discardableResult
    func play() -> Bool {
        playCallCount += 1
        return true
    }

    @discardableResult
    func stop() -> Bool {
        stopCallCount += 1
        return true
    }
}
