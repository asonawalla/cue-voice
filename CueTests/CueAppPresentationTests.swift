import Testing
@testable import Cue

@MainActor
struct CueAppPresentationTests {
    @Test func accessibilityRequiredPresentationShowsSetupPrompt() {
        var state = CueAppState(
            permissions: CuePermissionSnapshot(microphone: .granted, accessibility: .notGranted)
        )
        state.modelStatus = .ready

        let presentation = CueAppPresentation(state: state)

        #expect(presentation.needsPermissionPrompt)
        #expect(presentation.accessibilityPermission?.primaryAction == .requestAccessibilityPermission)
        #expect(presentation.accessibilityPermission?.secondaryAction == .openAccessibilitySettings)
    }

    @Test func failedModelPreparationPresentationOffersRetryAction() {
        var state = CueAppState(
            permissions: CuePermissionSnapshot(microphone: .granted, accessibility: .granted)
        )
        state.modelStatus = .failed("Model load failed")

        let presentation = CueAppPresentation(state: state)

        #expect(presentation.shouldOfferModelRetry)
    }

    @Test func nonModelFailurePresentationShowsError() {
        var state = CueAppState(
            permissions: CuePermissionSnapshot(microphone: .granted, accessibility: .granted)
        )
        state.modelStatus = .ready
        state.session = .failed(CueFailure.from(CueError.emptyTranscript))

        let presentation = CueAppPresentation(state: state)

        #expect(!presentation.shouldOfferModelRetry)
    }

    @Test func fullyConfiguredPresentationDoesNotNeedPermissionPrompt() {
        var state = CueAppState(
            permissions: CuePermissionSnapshot(microphone: .granted, accessibility: .granted)
        )
        state.modelStatus = .ready

        let presentation = CueAppPresentation(state: state)

        #expect(!presentation.needsPermissionPrompt)
        #expect(presentation.menuBarPrimaryStatus == "Ready")
        #expect(presentation.menuBarSecondaryStatus == nil)
    }
}
