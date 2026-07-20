import Foundation

struct CueStatusPresentation: Equatable {
    let symbolName: String
    let primary: String
    let secondary: String?
}

struct CueAppPresentation {
    let state: CueAppState

    var needsPermissionPrompt: Bool {
        !state.permissions.isFullyConfigured
    }

    var shouldOfferModelRetry: Bool {
        state.permissions.isFullyConfigured && state.modelStatus == .failed
    }

    var errorMessage: String? {
        state.currentFailure.map(CueCopy.errorMessage(for:))
    }

    var status: CueStatusPresentation {
        guard state.permissions.isMicrophoneReady else {
            return CueStatusPresentation(
                symbolName: "waveform.badge.exclamationmark",
                primary: "Microphone Required",
                secondary: CueCopy.permissionSetupSummary(state.permissions)
            )
        }

        guard state.permissions.isAccessibilityReady else {
            return CueStatusPresentation(
                symbolName: "waveform.badge.exclamationmark",
                primary: "Accessibility Required",
                secondary: CueCopy.permissionSetupSummary(state.permissions)
            )
        }

        switch state.session {
        case .idle:
            if state.modelStatus.isReady {
                return CueStatusPresentation(
                    symbolName: "waveform",
                    primary: "Ready",
                    secondary: nil
                )
            }

            return CueStatusPresentation(
                symbolName: "waveform.circle",
                primary: "Preparing Model",
                secondary: CueCopy.modelPreparationStatusTitle(state.modelStatus)
            )
        case .recording:
            return CueStatusPresentation(
                symbolName: "waveform.circle.fill",
                primary: "Recording",
                secondary: "Release the shortcut to stop recording."
            )
        case .transcribing:
            return CueStatusPresentation(
                symbolName: "waveform.badge.magnifyingglass",
                primary: "Transcribing",
                secondary: "WhisperKit is transcribing the latest clip."
            )
        case .pasting:
            return CueStatusPresentation(
                symbolName: "waveform.badge.plus",
                primary: "Pasting",
                secondary: "Cue is sending the latest transcript to the frontmost app."
            )
        case .failed(let error):
            return CueStatusPresentation(
                symbolName: "waveform.badge.exclamationmark",
                primary: "Error",
                secondary: CueCopy.errorMessage(for: error)
            )
        }
    }
}
