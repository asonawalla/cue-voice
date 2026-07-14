import Foundation

enum CueAppAction: Equatable {
    case requestMicrophonePermission
    case openMicrophoneSettings
    case requestAccessibilityPermission
    case openAccessibilitySettings
    case retryModelPreparation

    var title: String {
        switch self {
        case .requestMicrophonePermission:
            return "Grant Microphone Access"
        case .openMicrophoneSettings:
            return "Open Microphone Settings"
        case .requestAccessibilityPermission:
            return "Grant Accessibility Access"
        case .openAccessibilitySettings:
            return "Open Accessibility Settings"
        case .retryModelPreparation:
            return "Retry Model Preparation"
        }
    }
}

struct CuePermissionSectionPresentation {
    let detail: String
    let primaryAction: CueAppAction
    let secondaryAction: CueAppAction?
}

struct CueAppPresentation {
    let state: CueAppState

    var needsPermissionPrompt: Bool {
        !state.permissions.isFullyConfigured
    }

    var shouldOfferModelRetry: Bool {
        state.permissions.isFullyConfigured && !state.modelStatus.isReady && !state.modelStatus.isPreparing
    }

    var errorMessage: String? {
        if let failure = state.currentFailure {
            return CueCopy.failureMessage(failure)
        }

        return nil
    }

    var menuBarSymbolName: String {
        Self.makeMenuBarSymbolName(state: state)
    }

    var menuBarPrimaryStatus: String {
        Self.makeMenuBarPrimaryStatus(state: state)
    }

    var menuBarSecondaryStatus: String? {
        Self.makeMenuBarSecondaryStatus(state: state)
    }

    var microphonePermission: CuePermissionSectionPresentation? {
        Self.makeMicrophonePresentation(for: state.permissions.microphone)
    }

    var accessibilityPermission: CuePermissionSectionPresentation? {
        Self.makeAccessibilityPresentation(for: state.permissions.accessibility)
    }

    private static func makeMenuBarSymbolName(state: CueAppState) -> String {
        guard state.permissions.isFullyConfigured else {
            return "waveform.badge.exclamationmark"
        }

        switch state.session {
        case .recording:
            return "waveform.circle.fill"
        case .transcribing:
            return "waveform.badge.magnifyingglass"
        case .pasting:
            return "waveform.badge.plus"
        case .failed:
            return "waveform.badge.exclamationmark"
        case .idle:
            return state.modelStatus.isReady ? "waveform" : "waveform.circle"
        }
    }

    private static func makeMenuBarPrimaryStatus(state: CueAppState) -> String {
        guard state.permissions.isMicrophoneReady else {
            return "Microphone Required"
        }

        guard state.permissions.isAccessibilityReady else {
            return "Accessibility Required"
        }

        switch state.session {
        case .idle:
            guard state.modelStatus.isReady else {
                return "Preparing Model"
            }

            return "Ready"
        default:
            return CueCopy.sessionTitle(state.session)
        }
    }

    private static func makeMenuBarSecondaryStatus(state: CueAppState) -> String? {
        guard state.permissions.isFullyConfigured else {
            return CueCopy.permissionSetupSummary(state.permissions)
        }

        switch state.session {
        case .recording:
            return "Release the shortcut to stop recording."
        case .transcribing:
            return "WhisperKit is transcribing the latest clip."
        case .pasting:
            return "Cue is sending the latest transcript to the frontmost app."
        case .failed(let failure):
            return CueCopy.failureMessage(failure)
        case .idle:
            guard state.modelStatus.isReady else {
                return CueCopy.modelPreparationStatusTitle(state.modelStatus)
            }

            return nil
        }
    }

    private static func makeMicrophonePresentation(for permission: CuePermissionState) -> CuePermissionSectionPresentation? {
        switch permission {
        case .notDetermined:
            return CuePermissionSectionPresentation(
                detail: "Grant microphone access so Cue can record your speech.",
                primaryAction: .requestMicrophonePermission,
                secondaryAction: nil
            )
        case .denied:
            return CuePermissionSectionPresentation(
                detail: "Microphone access is blocked. Open System Settings to allow Cue to record.",
                primaryAction: .openMicrophoneSettings,
                secondaryAction: nil
            )
        case .granted:
            return nil
        }
    }

    private static func makeAccessibilityPresentation(for permission: CueAccessibilityPermissionState) -> CuePermissionSectionPresentation? {
        switch permission {
        case .notGranted:
            return CuePermissionSectionPresentation(
                detail: "Grant Accessibility permission so Cue can paste automatically into the focused app.",
                primaryAction: .requestAccessibilityPermission,
                secondaryAction: .openAccessibilitySettings
            )
        case .granted:
            return nil
        }
    }
}
