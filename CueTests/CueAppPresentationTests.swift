import Testing
@testable import Cue

@MainActor
struct CueAppPresentationTests {
    @Test func accessibilityRequiredPresentationShowsSetupPrompt() {
        var state = CueAppState.initial(
            permissionSnapshot: CuePermissionSnapshot(microphone: .granted, accessibility: .notGranted)
        )
        state.setup.modelStatus = .ready

        let presentation = CueAppPresentation(state: state)

        #expect(presentation.needsPermissionPrompt)
        #expect(presentation.accessibilityPermission.primaryAction == .requestAccessibilityPermission)
        #expect(presentation.accessibilityPermission.secondaryAction == .openAccessibilitySettings)
    }

    @Test func failedModelPreparationPresentationOffersRetryAction() {
        var state = CueAppState.initial(
            permissionSnapshot: CuePermissionSnapshot(microphone: .granted, accessibility: .granted)
        )
        state.setup.modelStatus = .failed("Model load failed")

        let presentation = CueAppPresentation(state: state)

        #expect(presentation.shouldOfferModelRetry)
    }

    @Test func nonModelFailurePresentationShowsError() {
        var state = CueAppState.initial(
            permissionSnapshot: CuePermissionSnapshot(microphone: .granted, accessibility: .granted)
        )
        state.setup.modelStatus = .ready
        state.session = .failed(CueFailure.from(CueError.emptyTranscript))

        let presentation = CueAppPresentation(state: state)

        #expect(!presentation.shouldOfferModelRetry)
    }

    @Test func fullyConfiguredPresentationDoesNotNeedPermissionPrompt() {
        var state = CueAppState.initial(
            permissionSnapshot: CuePermissionSnapshot(microphone: .granted, accessibility: .granted)
        )
        state.setup.modelStatus = .ready

        let presentation = CueAppPresentation(state: state)

        #expect(!presentation.needsPermissionPrompt)
        #expect(presentation.menuBarPrimaryStatus == "Ready")
        #expect(presentation.menuBarSecondaryStatus == nil)
    }
}
