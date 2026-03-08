import Foundation
import Testing
@testable import Cue

@MainActor
struct CueAppModelLifecycleTests {
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
            snapshot: CuePermissionSnapshot(microphone: .notDetermined, accessibility: .unavailable)
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

    @Test func launchWithAccessibilityUnavailableWarmsModelAndStillNeedsSetupPrompt() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .granted, accessibility: .unavailable)
        )
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()

        #expect(model.isReadyToRecord)
        #expect(model.isModelReady)
        #expect(model.needsPermissionPrompt)
        #expect(model.menuBarPrimaryStatus == "Clipboard Mode")
        #expect(model.automaticPasteWarningMessage == "Automatic paste is off. Cue will copy transcripts to the clipboard until Accessibility is enabled and Cue restarts.")
        #expect(model.accessibilityRestartMessage == "After you enable Cue in Accessibility settings, restart the app to turn automatic paste on.")
        #expect(model.showsAutomaticPasteIndicator)
    }
}
