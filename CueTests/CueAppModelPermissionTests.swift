import Foundation
import Testing
@testable import Cue

@MainActor
struct CueAppModelPermissionTests {
    @Test func firstPushToTalkBootstrapsPermissionsAndReturnsToIdle() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .notDetermined, inputMonitoring: .granted, accessibility: .granted)
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
        #expect(model.isReadyToRecord)
        #expect(transcriptionService.prepareCallCount == 1)
        #expect(transcriptionService.startRecordingCallCount == 0)
        #expect(model.sessionState == .idle)
    }

    @Test func secondPushToTalkStartsRecordingAfterPermissionBootstrap() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .notDetermined, inputMonitoring: .granted, accessibility: .granted)
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
        await model.handlePushToTalkPressed()

        #expect(permissionService.requestMicrophoneCallCount == 1)
        #expect(transcriptionService.prepareCallCount == 1)
        #expect(transcriptionService.startRecordingCallCount == 1)
        #expect(model.sessionState == .recording)
    }

    @Test func pushToTalkWithDeniedMicrophoneShowsErrorWithoutStartingRecording() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .denied, inputMonitoring: .granted, accessibility: .granted)
        )
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()
        await model.handlePushToTalkPressed()

        #expect(transcriptionService.startRecordingCallCount == 0)
        #expect(model.errorMessage == CueError.microphonePermissionDenied.errorDescription)
    }

    @Test func pushToTalkWithMissingInputMonitoringShowsErrorWithoutStartingRecording() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .granted, inputMonitoring: .unavailable, accessibility: .granted)
        )
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()
        await model.handlePushToTalkPressed()

        #expect(transcriptionService.startRecordingCallCount == 0)
        #expect(model.errorMessage == CueError.inputMonitoringPermissionDenied.errorDescription)
    }

    @Test func grantingMicrophonePermissionWarmsTheModelEvenWhenAccessibilityIsUnavailable() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .notDetermined, inputMonitoring: .granted, accessibility: .unavailable)
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
        #expect(!model.isReadyToRecord)
        #expect(transcriptionService.prepareCallCount == 1)
        #expect(model.isModelReady)
        #expect(!model.permissionSnapshot.canAutoPaste)
        #expect(model.needsPermissionPrompt)
        #expect(model.menuBarPrimaryStatus == "Accessibility Required")
    }

    @Test func openingInputMonitoringSettingsRequestsAccessBeforeShowingSystemSettings() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .granted, inputMonitoring: .unavailable, accessibility: .granted)
        )
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()
        model.openInputMonitoringSettings()

        #expect(permissionService.requestInputMonitoringCallCount == 1)
        #expect(permissionService.openedSettingsPermissions == [.inputMonitoring])
    }

    @Test func openingAccessibilitySettingsRequestsAccessBeforeShowingSystemSettings() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .granted, inputMonitoring: .granted, accessibility: .unavailable)
        )
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()
        model.openAccessibilitySettings()

        #expect(permissionService.requestAccessibilityCallCount == 1)
        #expect(permissionService.openedSettingsPermissions == [.accessibility])
    }
}
