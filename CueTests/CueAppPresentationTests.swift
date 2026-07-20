import Testing
@testable import Cue

@MainActor
struct CueAppPresentationTests {
    @Test func accessibilityRequiredPresentationShowsSetupStatus() {
        var state = CueAppState(
            permissions: CuePermissionSnapshot(microphone: .granted, accessibility: .notGranted)
        )
        state.modelStatus = .ready

        let presentation = CueAppPresentation(state: state)

        #expect(presentation.needsPermissionPrompt)
        #expect(presentation.status.primary == "Accessibility Required")
        #expect(presentation.status.symbolName == "waveform.badge.exclamationmark")
    }

    @Test func failedModelPreparationPresentationOffersRetryAction() {
        var state = CueAppState(
            permissions: CuePermissionSnapshot(microphone: .granted, accessibility: .granted)
        )
        state.modelStatus = .failed

        let presentation = CueAppPresentation(state: state)

        #expect(presentation.shouldOfferModelRetry)
    }

    @Test func nonModelFailurePresentationShowsError() {
        var state = CueAppState(
            permissions: CuePermissionSnapshot(microphone: .granted, accessibility: .granted)
        )
        state.modelStatus = .ready
        state.session = .failed(.emptyTranscript)

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
        #expect(presentation.status.primary == "Ready")
        #expect(presentation.status.secondary == nil)
    }
}
