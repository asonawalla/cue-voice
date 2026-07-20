import AppKit
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

@MainActor
struct CueRecordingPillPresentationTests {
    @Test func disabledPillHasNoPresentation() {
        var state = configuredState()
        state.session = .recording
        state.recordingPreviewText = "rough transcript"

        let presentation = CueRecordingPillPresentation(isEnabled: false, state: state)

        #expect(presentation.phase == nil)
        #expect(presentation.previewText == nil)
        #expect(!presentation.isPreviewUnavailable)
    }

    @Test func enabledPillStaysHiddenUntilCueIsReady() {
        var state = CueAppState(
            permissions: CuePermissionSnapshot(microphone: .granted, accessibility: .granted)
        )
        state.modelStatus = .loading

        #expect(CueRecordingPillPresentation(isEnabled: true, state: state).phase == nil)

        state.modelStatus = .ready
        state.permissions = CuePermissionSnapshot(microphone: .denied, accessibility: .granted)

        #expect(CueRecordingPillPresentation(isEnabled: true, state: state).phase == nil)
    }

    @Test func enabledPillExpandsAndShowsTrimmedRoughTextWhileRecording() {
        var state = configuredState()
        state.session = .recording
        state.recordingPreviewText = "  rough transcript in progress  "

        let presentation = CueRecordingPillPresentation(isEnabled: true, state: state)

        #expect(presentation.phase == .recording)
        #expect(presentation.previewText == "rough transcript in progress")
        #expect(!presentation.isPreviewUnavailable)
    }

    @Test func recordingPillSurfacesUnavailableLivePreview() {
        var state = configuredState()
        state.session = .recording
        state.isRecordingPreviewUnavailable = true

        let presentation = CueRecordingPillPresentation(isEnabled: true, state: state)

        #expect(presentation.phase == .recording)
        #expect(presentation.previewText == nil)
        #expect(presentation.isPreviewUnavailable)
    }

    @Test func enabledPillUsesCompactAndWorkingStatesOutsideRecording() {
        var state = configuredState()

        #expect(CueRecordingPillPresentation(isEnabled: true, state: state).phase == .compact)

        state.session = .transcribing
        #expect(CueRecordingPillPresentation(isEnabled: true, state: state).phase == .transcribing)

        state.session = .pasting
        #expect(CueRecordingPillPresentation(isEnabled: true, state: state).phase == .pasting)

        state.session = .failed(.emptyTranscript)
        #expect(CueRecordingPillPresentation(isEnabled: true, state: state).phase == .failed)
    }

    private func configuredState() -> CueAppState {
        var state = CueAppState(
            permissions: CuePermissionSnapshot(microphone: .granted, accessibility: .granted)
        )
        state.modelStatus = .ready
        return state
    }
}

struct CueRecordingPillPlacementTests {
    @Test func panelSizesMatchOnlyTheVisiblePillForEveryPhase() {
        #expect(CueRecordingPillLayout.size(for: .compact) == NSSize(width: 48, height: 18))
        #expect(CueRecordingPillLayout.size(for: .recording) == NSSize(width: 430, height: 68))
        #expect(CueRecordingPillLayout.size(for: .transcribing) == NSSize(width: 146, height: 34))
        #expect(CueRecordingPillLayout.size(for: .pasting) == NSSize(width: 112, height: 34))
        #expect(CueRecordingPillLayout.size(for: .failed) == NSSize(width: 138, height: 34))
    }

    @Test func defaultPlacementUsesTopCenterInsideTheSafeFrame() {
        let display = CueRecordingPillDisplayGeometry(
            identifier: "notched-display",
            safeFrame: NSRect(x: -1440, y: 40, width: 1440, height: 860)
        )
        let size = CueRecordingPillLayout.size(for: .compact)

        let placement = CueRecordingPillPlacementResolver.defaultPlacement(
            on: display,
            pillSize: size
        )
        let frame = CueRecordingPillPlacementResolver.frame(
            for: size,
            placement: placement,
            on: display
        )

        #expect(frame.midX == display.safeFrame.midX)
        #expect(frame.maxY == display.safeFrame.maxY - 8)
        #expect(display.safeFrame.contains(frame))
    }

    @Test func expandingNearAnEdgeClampsOnScreenWithoutChangingTheSavedAnchor() {
        let display = CueRecordingPillDisplayGeometry(
            identifier: "main",
            safeFrame: NSRect(x: 0, y: 0, width: 1000, height: 700)
        )
        let placement = CueRecordingPillPlacement(
            displayIdentifier: display.identifier,
            normalizedCenterX: 0.98,
            normalizedCenterY: 0.97
        )

        let compactFrame = CueRecordingPillPlacementResolver.frame(
            for: CueRecordingPillLayout.size(for: .compact),
            placement: placement,
            on: display
        )
        let recordingFrame = CueRecordingPillPlacementResolver.frame(
            for: CueRecordingPillLayout.size(for: .recording),
            placement: placement,
            on: display
        )
        let compactFrameAfterCollapse = CueRecordingPillPlacementResolver.frame(
            for: CueRecordingPillLayout.size(for: .compact),
            placement: placement,
            on: display
        )

        #expect(display.safeFrame.contains(recordingFrame))
        #expect(compactFrameAfterCollapse == compactFrame)
        #expect(recordingFrame.maxX == display.safeFrame.maxX)
    }

    @Test func normalizedPlacementSurvivesDisplayResolutionAndOriginChanges() {
        let originalDisplay = CueRecordingPillDisplayGeometry(
            identifier: "external",
            safeFrame: NSRect(x: -1920, y: 0, width: 1920, height: 1040)
        )
        let movedFrame = NSRect(x: -1512, y: 288, width: 48, height: 18)
        let placement = CueRecordingPillPlacementResolver.placement(
            for: movedFrame,
            on: originalDisplay
        )
        let reconfiguredDisplay = CueRecordingPillDisplayGeometry(
            identifier: "external",
            safeFrame: NSRect(x: 1728, y: -120, width: 2560, height: 1400)
        )

        let restoredFrame = CueRecordingPillPlacementResolver.frame(
            for: movedFrame.size,
            placement: placement,
            on: reconfiguredDisplay
        )
        let restoredPlacement = CueRecordingPillPlacementResolver.placement(
            for: restoredFrame,
            on: reconfiguredDisplay
        )

        #expect(abs(restoredPlacement.normalizedCenterX - placement.normalizedCenterX) < 0.000_001)
        #expect(abs(restoredPlacement.normalizedCenterY - placement.normalizedCenterY) < 0.000_001)
        #expect(reconfiguredDisplay.safeFrame.contains(restoredFrame))
    }

    @Test func displayResolutionUsesPanelCenterAcrossNegativeCoordinateDisplays() {
        let leftDisplay = CueRecordingPillDisplayGeometry(
            identifier: "left",
            safeFrame: NSRect(x: -1600, y: -100, width: 1600, height: 1000)
        )
        let mainDisplay = CueRecordingPillDisplayGeometry(
            identifier: "main",
            safeFrame: NSRect(x: 0, y: 0, width: 1728, height: 1080)
        )
        let frame = NSRect(x: -120, y: 300, width: 430, height: 68)

        let display = CueRecordingPillPlacementResolver.display(
            containing: frame,
            among: [leftDisplay, mainDisplay]
        )

        #expect(display?.identifier == "main")
    }

    @Test func invalidPersistedPlacementsAreRejected() {
        #expect(!CueRecordingPillPlacement(
            displayIdentifier: "main",
            normalizedCenterX: .nan,
            normalizedCenterY: 0.5
        ).isValid)
        #expect(!CueRecordingPillPlacement(
            displayIdentifier: "main",
            normalizedCenterX: 0.5,
            normalizedCenterY: 1.1
        ).isValid)
        #expect(CueRecordingPillPlacement(
            displayIdentifier: "main",
            normalizedCenterX: 0,
            normalizedCenterY: 1
        ).isValid)
    }
}
