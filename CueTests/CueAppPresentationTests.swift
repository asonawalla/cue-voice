import Testing
@testable import Cue

@MainActor
struct CueAppPresentationTests {
    @Test func setupRequiredPresentationExposesSharedSetupAndMenuMetadata() {
        var state = CueAppState.initial(
            permissionSnapshot: CuePermissionSnapshot(microphone: .granted, inputMonitoring: .granted, accessibility: .unavailable)
        )
        state.setup.modelStatus = .ready

        let presentation = CueAppPresentation(state: state)

        #expect(presentation.needsPermissionPrompt)
        #expect(presentation.menu.title == "Accessibility Required")
        #expect(presentation.menu.actions == [.openAccessibilitySettings, .openMainWindow, .quit])
        #expect(presentation.setup.accessibility.primaryAction == .openAccessibilitySettings)
    }

    @Test func failedModelPreparationPresentationOffersRetryAction() {
        var state = CueAppState.initial(
            permissionSnapshot: CuePermissionSnapshot(microphone: .granted, inputMonitoring: .granted, accessibility: .granted)
        )
        state.setup.modelStatus = .failed("Model load failed")

        let presentation = CueAppPresentation(state: state)

        #expect(presentation.shouldOfferModelRetry)
        #expect(presentation.menu.actions == [.retryModelPreparation, .openMainWindow, .quit])
    }

    @Test func nonModelFailurePresentationKeepsOpenCueAvailable() {
        var state = CueAppState.initial(
            permissionSnapshot: CuePermissionSnapshot(microphone: .granted, inputMonitoring: .granted, accessibility: .granted)
        )
        state.setup.modelStatus = .ready
        state.session = .failed(CueFailure.from(CueError.emptyTranscript))

        let presentation = CueAppPresentation(state: state)

        #expect(!presentation.shouldOfferModelRetry)
        #expect(presentation.menu.actions == [.openMainWindow, .quit])
    }
}
