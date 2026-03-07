import Foundation
import Testing
@testable import Cue

@MainActor
struct CueTests {
    @Test func launchWithGrantedMicrophoneWarmsTheModelWithoutLeavingIdle() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService()
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()

        #expect(transcriptionService.prepareCallCount == 1)
        #expect(model.phase == .idle)
        #expect(model.isReadyToRecord)
        #expect(model.isModelReady)
        #expect(model.errorMessage == nil)
        #expect(permissionService.requestPasteCallCount == 0)
        #expect(insertionService.insertCallCount == 0)
    }

    @Test func launchWithMissingMicrophoneRequestsSetupAndSkipsModelWarmup() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .notDetermined, paste: .unavailable)
        )
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()

        #expect(!model.isReadyToRecord)
        #expect(model.shouldShowSetupExperience)
        #expect(model.setupWindowPresentationToken == 1)
        #expect(transcriptionService.prepareCallCount == 0)
        #expect(model.phase == .idle)
    }

    @Test func pushToTalkRequestsMicrophonePermissionWhenUndeterminedAndStartsRecording() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .notDetermined, paste: .unavailable)
        )
        permissionService.microphoneRequestResult = .granted

        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()
        await model.handlePushToTalkPressed()

        #expect(permissionService.requestMicrophoneCallCount == 1)
        #expect(permissionService.requestPasteCallCount == 1)
        #expect(model.isReadyToRecord)
        #expect(transcriptionService.prepareCallCount == 1)
        #expect(transcriptionService.startRecordingCallCount == 1)
        #expect(model.phase == .recording)
    }

    @Test func pushToTalkWithDeniedMicrophoneDoesNotReopenSetupWindowAfterInitialLaunch() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .denied, paste: .unavailable)
        )
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()
        await model.handlePushToTalkPressed()

        #expect(model.setupWindowPresentationToken == 1)
        #expect(transcriptionService.startRecordingCallCount == 0)
        #expect(model.phase == .error)
        #expect(model.errorMessage == CueError.microphonePermissionDenied.errorDescription)
    }

    @Test func pushToTalkWhileAutomaticPasteIsUnavailableStillStartsRecording() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .granted, paste: .unavailable)
        )
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()
        #expect(model.menuBarPrimaryStatus == "Clipboard Mode")
        await model.handlePushToTalkPressed()

        #expect(permissionService.requestPasteCallCount == 1)
        #expect(model.setupWindowPresentationToken == 0)
        #expect(transcriptionService.startRecordingCallCount == 1)
        #expect(model.phase == .recording)
        #expect(model.automaticPasteWarningMessage == "Automatic paste is off. Cue will copy transcripts to the clipboard until Accessibility is enabled.")
    }

    @Test func grantingMicrophonePermissionWarmsTheModelEvenWhenPasteIsUnavailable() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .notDetermined, paste: .unavailable)
        )
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()
        permissionService.microphoneRequestResult = .granted

        await model.requestMicrophonePermission()

        #expect(permissionService.requestMicrophoneCallCount == 1)
        #expect(permissionService.requestPasteCallCount == 1)
        #expect(model.isReadyToRecord)
        #expect(transcriptionService.prepareCallCount == 1)
        #expect(model.isModelReady)
        #expect(!model.permissionSnapshot.canAutoPaste)
        #expect(model.automaticPasteWarningMessage == "Automatic paste is off. Cue will copy transcripts to the clipboard until Accessibility is enabled.")
    }

    @Test func requestingPastePermissionUpdatesAutomationStateWithoutBlockingRecording() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .granted, paste: .unavailable)
        )
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()
        permissionService.pasteRequestResult = .available

        await model.requestPastePermission()

        #expect(permissionService.requestPasteCallCount == 2)
        #expect(model.isReadyToRecord)
        #expect(model.permissionSnapshot.canAutoPaste)
        #expect(transcriptionService.prepareCallCount == 1)
    }

    @Test func launchWithPasteUnavailableRequestsAccessibilityByDefaultAndSurfacesClipboardMode() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .granted, paste: .unavailable)
        )
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()

        #expect(permissionService.requestPasteCallCount == 1)
        #expect(model.isReadyToRecord)
        #expect(model.isModelReady)
        #expect(model.menuBarPrimaryStatus == "Clipboard Mode")
        #expect(model.automaticPasteWarningMessage == "Automatic paste is off. Cue will copy transcripts to the clipboard until Accessibility is enabled.")
        #expect(model.showsAutomaticPasteIndicator)
    }

    @Test func handlePushToTalkReleasedStoresTranscriptAndPastedResult() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService()
        transcriptionService.result = CueTranscriptionResult(
            text: "milestone three transcript",
            language: "en",
            recordingDuration: 2.0,
            modelLoadDuration: 0.25,
            pipelineDuration: 0.5
        )
        insertionService.result = CueInsertionResult(
            delivery: .pasted,
            targetAppName: "TextEdit",
            targetBundleIdentifier: "com.apple.TextEdit",
            pasteDuration: 0.18,
            clipboardRestoreOutcome: .restored
        )
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()
        await model.handlePushToTalkPressed()
        await model.handlePushToTalkReleased()

        #expect(model.phase == .idle)
        #expect(model.transcript == "milestone three transcript")
        #expect(model.lastInsertionResult == insertionService.result)
        #expect(model.latencyMetrics != nil)
        #expect(model.latencyMetrics?.recordingDuration == 2.0)
        #expect(model.latencyMetrics?.pasteDuration == 0.18)
        #expect((model.latencyMetrics?.totalDuration ?? 0) >= 2.18)
        #expect(transcriptionService.startRecordingCallCount == 1)
        #expect(transcriptionService.stopRecordingCallCount == 1)
        #expect(insertionService.insertCallCount == 1)
    }

    @Test func clipboardFallbackKeepsTranscriptAndReturnsToIdle() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .granted, paste: .unavailable)
        )
        insertionService.result = CueInsertionResult(
            delivery: .copiedToClipboard(.accessibilityPermissionMissing),
            targetAppName: "TextEdit",
            targetBundleIdentifier: "com.apple.TextEdit",
            pasteDuration: 0,
            clipboardRestoreOutcome: .notNeededBecauseTranscriptStayedOnClipboard
        )
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()
        await model.handlePushToTalkPressed()
        await model.handlePushToTalkReleased()

        #expect(model.phase == .idle)
        #expect(model.transcript == transcriptionService.result.text)
        #expect(model.lastInsertionResult?.delivery == .copiedToClipboard(.accessibilityPermissionMissing))
        #expect(model.errorMessage == nil)
        #expect(model.automaticPasteWarningMessage == CueClipboardFallbackReason.accessibilityPermissionMissing.description)
        #expect(insertionService.insertCallCount == 1)
    }

    @Test func launchFailureMovesStateToErrorWhenMicrophoneIsSatisfied() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService()
        transcriptionService.prepareError = CueError.modelDownloadFailed("offline")

        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()

        #expect(model.phase == .error)
        #expect(model.errorMessage == "Cue could not prepare the base.en model: offline")
        #expect(insertionService.insertCallCount == 0)
    }

    @Test func transcriptionFailureDoesNotAttemptPaste() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService()
        transcriptionService.stopRecordingError = CueError.transcriptionFailed("backend offline")
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()
        await model.handlePushToTalkPressed()
        await model.handlePushToTalkReleased()

        #expect(model.phase == .error)
        #expect(model.errorMessage == "Cue could not transcribe the recording: backend offline")
        #expect(insertionService.insertCallCount == 0)
    }
}

@MainActor
private final class FakeTranscriptionService: TranscriptionService {
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
private final class FakeTextInsertionService: TextInsertionService {
    var insertCallCount = 0
    var insertError: Error?
    var result = CueInsertionResult(
        delivery: .pasted,
        targetAppName: "TextEdit",
        targetBundleIdentifier: "com.apple.TextEdit",
        pasteDuration: 0.12,
        clipboardRestoreOutcome: .restored
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
private final class FakePermissionService: PermissionService {
    var snapshot: CuePermissionSnapshot
    var currentSnapshotCallCount = 0
    var requestMicrophoneCallCount = 0
    var requestPasteCallCount = 0
    var openedSettingsPermissions: [CuePermissionKind] = []
    var microphoneRequestResult: CuePermissionState?
    var pasteRequestResult: CueAutomationPermissionState?

    init(snapshot: CuePermissionSnapshot = CuePermissionSnapshot(microphone: .granted, paste: .available)) {
        self.snapshot = snapshot
    }

    func currentPermissionSnapshot() -> CuePermissionSnapshot {
        currentSnapshotCallCount += 1
        return snapshot
    }

    func requestMicrophonePermission() async -> CuePermissionState {
        requestMicrophoneCallCount += 1

        if let microphoneRequestResult {
            snapshot = CuePermissionSnapshot(microphone: microphoneRequestResult, paste: snapshot.paste)
        }

        return snapshot.microphone
    }

    func requestPastePermission() async -> CueAutomationPermissionState {
        requestPasteCallCount += 1

        if let pasteRequestResult {
            snapshot = CuePermissionSnapshot(microphone: snapshot.microphone, paste: pasteRequestResult)
        }

        return snapshot.paste
    }

    func openSystemSettings(for permission: CuePermissionKind) {
        openedSettingsPermissions.append(permission)
    }
}
