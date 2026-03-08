import Testing
@testable import Cue

@MainActor
struct CueAppPresentationTests {
    @Test func clipboardModePresentationExposesSharedSetupAndMenuMetadata() {
        var state = CueAppState.initial(
            permissionSnapshot: CuePermissionSnapshot(microphone: .granted, accessibility: .unavailable)
        )
        state.setup.modelStatus = .ready

        let presentation = CueAppPresentation(state: state)

        #expect(presentation.needsPermissionPrompt)
        #expect(presentation.menu.title == "Clipboard Mode")
        #expect(presentation.menu.actions == [.openAccessibilitySettings, .restartApplication, .openMainWindow, .quit])
        #expect(presentation.setup.accessibility.primaryAction == .openAccessibilitySettings)
        #expect(presentation.setup.accessibility.secondaryAction == .restartApplication)
    }

    @Test func failedModelPreparationPresentationOffersRetryAction() {
        var state = CueAppState.initial(
            permissionSnapshot: CuePermissionSnapshot(microphone: .granted, accessibility: .granted)
        )
        state.setup.modelStatus = .failed("Model load failed")

        let presentation = CueAppPresentation(state: state)

        #expect(presentation.shouldOfferModelRetry)
        #expect(presentation.menu.actions == [.retryModelPreparation, .quit])
    }
}
