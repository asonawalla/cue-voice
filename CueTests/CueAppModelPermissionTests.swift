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
        model.handlePushToTalkPressed()
        await yieldUntil { permissionService.requestMicrophoneCallCount == 1 }

        #expect(permissionService.requestMicrophoneCallCount == 1)
        #expect(!model.state.permissions.isFullyConfigured)
        #expect(transcriptionService.prepareCallCount == 0)
        #expect(transcriptionService.startRecordingCallCount == 0)
        #expect(model.state.session == .idle)
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
        model.handlePushToTalkPressed()

        #expect(transcriptionService.startRecordingCallCount == 0)
        #expect(model.presentation.errorMessage == CueCopy.errorMessage(for: CueError.microphonePermissionDenied))
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
        model.handlePushToTalkPressed()

        #expect(transcriptionService.startRecordingCallCount == 0)
        #expect(model.presentation.errorMessage == CueCopy.errorMessage(for: CueError.accessibilityPermissionDenied))
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
        model.handlePushToTalkPressed()
        await model.refreshPermissions()

        #expect(
            model.state.session == .failed(CueFailure.from(CueError.accessibilityPermissionDenied))
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
        model.handlePushToTalkPressed()
        permissionService.snapshot = CuePermissionSnapshot(microphone: .granted, accessibility: .granted)

        await model.refreshPermissions()

        #expect(model.state.session == .idle)
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
        model.handlePushToTalkPressed()
        permissionService.snapshot = CuePermissionSnapshot(microphone: .granted, accessibility: .notGranted)

        await model.refreshPermissions()

        #expect(model.state.session == .idle)
    }

    @Test func refreshPermissionsDoesNotClearNonPermissionFailures() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        insertionService.insertError = CueError.pasteFailed("paste unavailable")
        let permissionService = FakePermissionService()
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()
        model.handlePushToTalkPressed()
        await yieldUntil { model.state.session == .recording }
        model.handlePushToTalkReleased()
        await yieldUntil { model.state.currentFailure != nil }

        await model.refreshPermissions()

        #expect(model.state.session == .failed(CueFailure.from(CueError.pasteFailed("paste unavailable"))))
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
        #expect(!model.state.permissions.isFullyConfigured)
        #expect(transcriptionService.prepareCallCount == 0)
        #expect(model.presentation.needsPermissionPrompt)
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

    private func yieldUntil(
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
}
