import Foundation
@testable import Cue

@MainActor
final class FakeTranscriptionService: TranscriptionService {
    var prepareCallCount = 0
    var disableRecordingPreviewCallCount = 0
    var startRecordingCallCount = 0
    var stopRecordingCallCount = 0
    var prepareError: Error?
    var startRecordingError: Error?
    var stopRecordingError: Error?
    var suspendsPrepareModel = false
    var suspendsStartRecording = false
    var suspendsStopRecording = false
    var lastSaveDebugCapture = false
    var previewHandler: TranscriptionPreviewHandler?
    var previewUpdateDuringStart: TranscriptionPreviewUpdate?
    private var prepareModelContinuation: CheckedContinuation<Void, Never>?
    private var startRecordingContinuation: CheckedContinuation<Void, Never>?
    private var stopRecordingContinuation: CheckedContinuation<Void, Never>?
    var result = "milestone transcript"

    @MainActor
    func prepareModel(reportStatus: @escaping TranscriptionStatusHandler) async throws {
        prepareCallCount += 1

        if suspendsPrepareModel {
            await withCheckedContinuation { continuation in
                prepareModelContinuation = continuation
            }
        }

        if let prepareError {
            throw prepareError
        }

        _ = reportStatus
    }

    func resumePrepareModel() {
        let continuation = prepareModelContinuation
        prepareModelContinuation = nil
        continuation?.resume()
    }

    @MainActor
    func disableRecordingPreview() async {
        disableRecordingPreviewCallCount += 1
        previewHandler = nil
    }

    @MainActor
    func startRecording(reportPreview: TranscriptionPreviewHandler?) async throws {
        startRecordingCallCount += 1
        previewHandler = reportPreview
        if let previewUpdateDuringStart {
            reportPreview?(previewUpdateDuringStart)
        }

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

    func reportPreview(_ text: String) {
        previewHandler?(.text(text))
    }

    func reportPreviewUnavailable() {
        previewHandler?(.unavailable)
    }

    @MainActor
    func stopRecording(saveDebugCapture: Bool) async throws -> String {
        stopRecordingCallCount += 1
        lastSaveDebugCapture = saveDebugCapture

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
    var pasteDuration: TimeInterval = 0.12

    func insert(_ text: String) async throws -> CueInsertionResult {
        insertCallCount += 1
        insertedTexts.append(text)

        if let insertError {
            throw insertError
        }

        return CueInsertionResult(
            pasteDuration: pasteDuration,
            pasteCommandPostedAt: Date()
        )
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

@MainActor
final class CueAppModelTestRig {
    let transcriptionService: FakeTranscriptionService
    let insertionService: FakeTextInsertionService
    let permissionService: FakePermissionService
    let soundService: FakeSoundService
    let defaults: UserDefaults
    let notificationCenter: NotificationCenter
    let debugCaptureDirectory: URL
    let model: CueAppModel

    private let defaultsSuiteName: String
    private let temporaryRoot: URL

    init(
        permissions: CuePermissionSnapshot = CuePermissionSnapshot(
            microphone: .granted,
            accessibility: .granted
        )
    ) {
        let defaultsSuiteName = "CueTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(defaultsSuiteName, isDirectory: true)
        let debugCaptureDirectory = temporaryRoot
            .appendingPathComponent("DebugCaptures", isDirectory: true)
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(snapshot: permissions)
        let soundService = FakeSoundService()
        let notificationCenter = NotificationCenter()

        self.transcriptionService = transcriptionService
        self.insertionService = insertionService
        self.permissionService = permissionService
        self.soundService = soundService
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.debugCaptureDirectory = debugCaptureDirectory
        self.defaultsSuiteName = defaultsSuiteName
        self.temporaryRoot = temporaryRoot
        self.model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            soundService: soundService,
            defaults: defaults,
            notificationCenter: notificationCenter,
            debugCaptureDirectory: debugCaptureDirectory
        )
    }

    func makeModel() -> CueAppModel {
        CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            soundService: soundService,
            defaults: defaults,
            notificationCenter: notificationCenter,
            debugCaptureDirectory: debugCaptureDirectory
        )
    }

    deinit {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: temporaryRoot)
    }
}

@MainActor
func yieldUntil(
    maxYields: Int = 20,
    condition: @escaping @MainActor () -> Bool
) async {
    for _ in 0..<maxYields {
        if condition() {
            return
        }

        await Task.yield()
    }
}
