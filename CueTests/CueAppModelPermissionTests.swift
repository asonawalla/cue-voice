import Foundation
import Testing
@testable import Cue

@MainActor
struct CueAppModelPermissionTests {
    @Test func firstPushToTalkBootstrapsPermissionsAndReturnsToIdle() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .notDetermined, accessibility: .notGranted)
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
        #expect(!model.isReadyToRecord)
        #expect(transcriptionService.prepareCallCount == 0)
        #expect(transcriptionService.startRecordingCallCount == 0)
        #expect(model.sessionState == .idle)
    }

    @Test func pushToTalkWithDeniedMicrophoneShowsErrorWithoutStartingRecording() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .denied, accessibility: .notGranted)
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
        #expect(model.errorMessage == CueCopy.errorMessage(for: CueError.microphonePermissionDenied))
    }

    @Test func pushToTalkWithoutAccessibilityShowsError() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .granted, accessibility: .notGranted)
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
        #expect(model.errorMessage == CueCopy.errorMessage(for: CueError.accessibilityPermissionDenied))
    }

    @Test func refreshPermissionsKeepsAccessibilityFailureUntilAccessibilityIsGranted() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .granted, accessibility: .notGranted)
        )
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()
        await model.handlePushToTalkPressed()
        await model.refreshPermissions()

        #expect(
            model.sessionState == .failed(CueFailure.from(CueError.accessibilityPermissionDenied))
        )
    }

    @Test func refreshPermissionsClearsAccessibilityFailureAfterAccessibilityIsGranted() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .granted, accessibility: .notGranted)
        )
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()
        await model.handlePushToTalkPressed()
        permissionService.snapshot = CuePermissionSnapshot(microphone: .granted, accessibility: .granted)

        await model.refreshPermissions()

        #expect(model.sessionState == .idle)
    }

    @Test func refreshPermissionsClearsMicrophoneFailureWhenMicrophoneBecomesReady() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .denied, accessibility: .notGranted)
        )
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()
        await model.handlePushToTalkPressed()
        permissionService.snapshot = CuePermissionSnapshot(microphone: .granted, accessibility: .notGranted)

        await model.refreshPermissions()

        #expect(model.sessionState == .idle)
    }

    @Test func refreshPermissionsDoesNotClearNonPermissionFailures() async throws {
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
        model.state.session = .failed(CueFailure.from(CueError.emptyTranscript))

        await model.refreshPermissions()

        #expect(model.sessionState == .failed(CueFailure.from(CueError.emptyTranscript)))
    }

    @Test func grantingMicrophonePermissionDoesNotWarmModelWithoutAccessibility() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .notDetermined, accessibility: .notGranted)
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
        #expect(transcriptionService.prepareCallCount == 0)
        #expect(model.needsPermissionPrompt)
    }

    @Test func openingAccessibilitySettingsRequestsAccessBeforeShowingSystemSettings() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .granted, accessibility: .notGranted)
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
