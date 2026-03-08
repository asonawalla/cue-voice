import Foundation
import Testing
@testable import Cue

@MainActor
struct CueAppModelLifecycleTests {
    @Test func launchWithGrantedPermissionsWarmsTheModelWithoutLeavingIdle() async throws {
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
        #expect(model.sessionState == .idle)
        #expect(model.isReadyToRecord)
        #expect(model.isModelReady)
        #expect(!model.needsPermissionPrompt)
        #expect(model.errorMessage == nil)
        #expect(insertionService.insertCallCount == 0)
    }

    @Test func launchWithMissingMicrophoneSkipsModelWarmupAndStaysIdle() async throws {
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

        #expect(!model.isReadyToRecord)
        #expect(transcriptionService.prepareCallCount == 0)
        #expect(model.sessionState == .idle)
        #expect(model.needsPermissionPrompt)
    }

    @Test func launchWithMissingAccessibilitySkipsModelWarmupAndNeedsSetupPrompt() async throws {
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

        #expect(!model.isReadyToRecord)
        #expect(transcriptionService.prepareCallCount == 0)
        #expect(model.sessionState == .idle)
        #expect(model.needsPermissionPrompt)
        #expect(model.menuBarPrimaryStatus == "Accessibility Required")
    }
}
