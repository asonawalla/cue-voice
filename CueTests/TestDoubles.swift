import Foundation
@testable import Cue

@MainActor
final class FakeTranscriptionService: TranscriptionService {
    var statusHandler: TranscriptionStatusHandler?

    var prepareCallCount = 0
    var startRecordingCallCount = 0
    var stopRecordingCallCount = 0
    var prepareError: Error?
    var startRecordingError: Error?
    var stopRecordingError: Error?
    var suspendsStartRecording = false
    var suspendsStopRecording = false
    private var startRecordingContinuation: CheckedContinuation<Void, Never>?
    private var stopRecordingContinuation: CheckedContinuation<Void, Never>?
    var result = "milestone transcript"

    @MainActor
    func prepareModel() async throws {
        prepareCallCount += 1

        if let prepareError {
            throw prepareError
        }

        statusHandler?(.ready)
    }

    @MainActor
    func startRecording() async throws {
        startRecordingCallCount += 1

        if suspendsStartRecording {
            await withCheckedContinuation { continuation in
                startRecordingContinuation = continuation
            }
        }

        if let startRecordingError {
            throw startRecordingError
        }
    }

    func resumeStartRecording() {
        let continuation = startRecordingContinuation
        startRecordingContinuation = nil
        continuation?.resume()
    }

    @MainActor
    func stopRecording() async throws -> String {
        stopRecordingCallCount += 1

        if suspendsStopRecording {
            await withCheckedContinuation { continuation in
                stopRecordingContinuation = continuation
            }
        }

        if let stopRecordingError {
            throw stopRecordingError
        }

        return result
    }

    func resumeStopRecording() {
        let continuation = stopRecordingContinuation
        stopRecordingContinuation = nil
        continuation?.resume()
    }
}

@MainActor
final class FakeTextInsertionService: TextInsertionService {
    var insertCallCount = 0
    var insertedTexts: [String] = []
    var insertError: Error?
    var result = CueInsertionResult(
        pasteDuration: 0.12,
        pasteCommandPostedAt: Date()
    )

    func insert(_ text: String) async throws -> CueInsertionResult {
        insertCallCount += 1
        insertedTexts.append(text)

        if let insertError {
            throw insertError
        }

        return result
    }
}

@MainActor
final class FakePermissionService: PermissionService {
    var snapshot: CuePermissionSnapshot
    var requestMicrophoneCallCount = 0
    var requestAccessibilityCallCount = 0
    var openedSettingsPermissions: [CuePermissionKind] = []
    var microphoneRequestResult: CuePermissionState?

    init(snapshot: CuePermissionSnapshot = CuePermissionSnapshot(microphone: .granted, accessibility: .granted)) {
        self.snapshot = snapshot
    }

    func currentPermissionSnapshot() -> CuePermissionSnapshot {
        return snapshot
    }

    func requestMicrophonePermission() async {
        requestMicrophoneCallCount += 1

        if let microphoneRequestResult {
            snapshot = CuePermissionSnapshot(microphone: microphoneRequestResult, accessibility: snapshot.accessibility)
        }
    }

    func requestAccessibilityPermission() {
        requestAccessibilityCallCount += 1
    }

    func openSystemSettings(for permission: CuePermissionKind) {
        openedSettingsPermissions.append(permission)
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
