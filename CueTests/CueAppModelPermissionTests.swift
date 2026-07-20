import Foundation
import Testing
@testable import Cue

@MainActor
struct CueAppModelPermissionTests {
    @Test func firstPushToTalkBootstrapsPermissionsAndReturnsToIdle() async {
        let rig = CueAppModelTestRig(
            permissions: CuePermissionSnapshot(microphone: .notDetermined, accessibility: .notGranted)
        )
        rig.permissionService.microphoneRequestResult = .granted
        let model = rig.model

        await model.launch()
        model.handlePushToTalkPressed()
        await yieldUntil { rig.permissionService.requestMicrophoneCallCount == 1 }

        #expect(rig.permissionService.requestMicrophoneCallCount == 1)
        #expect(!model.state.permissions.isFullyConfigured)
        #expect(rig.transcriptionService.prepareCallCount == 0)
        #expect(rig.transcriptionService.startRecordingCallCount == 0)
        #expect(model.state.session == .idle)
    }

    @Test func pushToTalkWithDeniedMicrophoneShowsErrorWithoutStartingRecording() async {
        let rig = CueAppModelTestRig(
            permissions: CuePermissionSnapshot(microphone: .denied, accessibility: .notGranted)
        )
        let model = rig.model

        await model.launch()
        model.handlePushToTalkPressed()

        #expect(rig.transcriptionService.startRecordingCallCount == 0)
        #expect(model.presentation.errorMessage == CueCopy.errorMessage(for: CueError.microphonePermissionDenied))
    }

    @Test func pushToTalkWithoutAccessibilityShowsError() async {
        let rig = CueAppModelTestRig(
            permissions: CuePermissionSnapshot(microphone: .granted, accessibility: .notGranted)
        )
        let model = rig.model

        await model.launch()
        model.handlePushToTalkPressed()

        #expect(rig.transcriptionService.startRecordingCallCount == 0)
        #expect(model.presentation.errorMessage == CueCopy.errorMessage(for: CueError.accessibilityPermissionDenied))
    }

    @Test func refreshPermissionsKeepsAccessibilityFailureUntilAccessibilityIsGranted() async {
        let rig = CueAppModelTestRig(
            permissions: CuePermissionSnapshot(microphone: .granted, accessibility: .notGranted)
        )
        let model = rig.model

        await model.launch()
        model.handlePushToTalkPressed()
        await model.refreshPermissions()

        #expect(model.state.session == .failed(.accessibilityPermissionDenied))
    }

    @Test func refreshPermissionsClearsAccessibilityFailureAfterAccessibilityIsGranted() async {
        let rig = CueAppModelTestRig(
            permissions: CuePermissionSnapshot(microphone: .granted, accessibility: .notGranted)
        )
        let model = rig.model

        await model.launch()
        model.handlePushToTalkPressed()
        rig.permissionService.snapshot = CuePermissionSnapshot(microphone: .granted, accessibility: .granted)

        await model.refreshPermissions()

        #expect(model.state.session == .idle)
    }

    @Test func refreshPermissionsClearsMicrophoneFailureWhenMicrophoneBecomesReady() async {
        let rig = CueAppModelTestRig(
            permissions: CuePermissionSnapshot(microphone: .denied, accessibility: .notGranted)
        )
        let model = rig.model

        await model.launch()
        model.handlePushToTalkPressed()
        rig.permissionService.snapshot = CuePermissionSnapshot(microphone: .granted, accessibility: .notGranted)

        await model.refreshPermissions()

        #expect(model.state.session == .idle)
    }

    @Test func refreshPermissionsDoesNotClearNonPermissionFailures() async {
        let rig = CueAppModelTestRig()
        rig.insertionService.insertError = CueError.pasteFailed("paste unavailable")
        let model = rig.model

        await model.launch()
        model.handlePushToTalkPressed()
        await yieldUntil { model.state.session == .recording }
        model.handlePushToTalkReleased()
        await yieldUntil { model.state.currentFailure != nil }

        await model.refreshPermissions()

        #expect(model.state.session == .failed(.pasteFailed("paste unavailable")))
    }

    @Test func grantingMicrophonePermissionDoesNotWarmModelWithoutAccessibility() async {
        let rig = CueAppModelTestRig(
            permissions: CuePermissionSnapshot(microphone: .notDetermined, accessibility: .notGranted)
        )
        let model = rig.model

        await model.launch()
        rig.permissionService.microphoneRequestResult = .granted

        await model.requestMicrophonePermission()

        #expect(rig.permissionService.requestMicrophoneCallCount == 1)
        #expect(!model.state.permissions.isFullyConfigured)
        #expect(rig.transcriptionService.prepareCallCount == 0)
        #expect(model.presentation.needsPermissionPrompt)
    }

    @Test func openingAccessibilitySettingsRequestsAccessBeforeShowingSystemSettings() async {
        let rig = CueAppModelTestRig(
            permissions: CuePermissionSnapshot(microphone: .granted, accessibility: .notGranted)
        )
        let model = rig.model

        await model.launch()
        model.openAccessibilitySettings()

        #expect(rig.permissionService.requestAccessibilityCallCount == 1)
        #expect(rig.permissionService.openedSettingsPermissions == [.accessibility])
    }
}
