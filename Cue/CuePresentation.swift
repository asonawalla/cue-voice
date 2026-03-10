import Foundation

enum CueAppAction: Hashable {
    case requestMicrophonePermission
    case openMicrophoneSettings
    case requestAccessibilityPermission
    case openAccessibilitySettings
    case restartApplication
    case retryModelPreparation
    case quit

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
        case .restartApplication:
            return "Restart Cue"
        case .retryModelPreparation:
            return "Retry Model Preparation"
        case .quit:
            return "Quit Cue"
        }
    }
}

struct CuePermissionSectionPresentation: Equatable {
    let detail: String
    let primaryAction: CueAppAction?
    let secondaryAction: CueAppAction?
}

struct CueSetupPresentation: Equatable {
    let statusSummary: String
    let microphone: CuePermissionSectionPresentation
    let accessibility: CuePermissionSectionPresentation
}

struct CueAppPresentation: Equatable {
    let needsPermissionPrompt: Bool
    let shouldOfferModelRetry: Bool
    let menuBarSymbolName: String
    let menuBarPrimaryStatus: String
    let menuBarSecondaryStatus: String?
    let setup: CueSetupPresentation

    init(state: CueAppState) {
        let hasLoadedPermissions = state.setup.hasLoadedPermissions
        let permissions = state.setup.permissions

        needsPermissionPrompt = hasLoadedPermissions && !permissions.isFullyConfigured
        shouldOfferModelRetry = state.isReadyToRecord && !state.isModelReady && !state.setup.modelStatus.isPreparing

        menuBarSymbolName = CueAppPresentation.makeMenuBarSymbolName(state: state)
        menuBarPrimaryStatus = CueAppPresentation.makeMenuBarPrimaryStatus(state: state)
        menuBarSecondaryStatus = CueAppPresentation.makeMenuBarSecondaryStatus(state: state)

        setup = CueSetupPresentation(
            statusSummary: permissions.setupSummary,
            microphone: CueAppPresentation.makeMicrophonePresentation(for: permissions.microphone),
            accessibility: CueAppPresentation.makeAccessibilityPresentation(for: permissions.accessibility)
        )
    }

    private static func makeMenuBarSymbolName(state: CueAppState) -> String {
        guard state.setup.hasLoadedPermissions else {
            return "waveform.circle"
        }

        guard state.setup.permissions.isFullyConfigured else {
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
            return state.isModelReady ? "waveform" : "waveform.circle"
        }
    }

    private static func makeMenuBarPrimaryStatus(state: CueAppState) -> String {
        guard state.setup.hasLoadedPermissions else {
            return "Checking Permissions"
        }

        guard state.setup.permissions.isMicrophoneReady else {
            return "Microphone Required"
        }

        guard state.setup.permissions.isAccessibilityReady else {
            return "Accessibility Required"
        }

        switch state.session {
        case .idle:
            guard state.isModelReady else {
                return "Preparing Model"
            }

            return "Ready"
        default:
            return state.session.title
        }
    }

    private static func makeMenuBarSecondaryStatus(state: CueAppState) -> String? {
        guard state.setup.hasLoadedPermissions else {
            return "Cue is checking which permissions are available."
        }

        guard state.setup.permissions.isFullyConfigured else {
            return state.setup.permissions.setupSummary
        }

        switch state.session {
        case .recording:
            return "Release the shortcut to stop recording."
        case .transcribing:
            return "WhisperKit is transcribing the latest clip."
        case .pasting:
            return "Cue is sending the latest transcript to the frontmost app."
        case .failed(let failure):
            return failure.message
        case .idle:
            guard state.isModelReady else {
                return state.setup.modelStatus.title
            }

            return nil
        }
    }

    private static func makeMicrophonePresentation(for permission: CuePermissionState) -> CuePermissionSectionPresentation {
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
            return CuePermissionSectionPresentation(
                detail: "Microphone is ready.",
                primaryAction: nil,
                secondaryAction: nil
            )
        }
    }

    private static func makeAccessibilityPresentation(for permission: CueAccessibilityPermissionState) -> CuePermissionSectionPresentation {
        switch permission {
        case .notGranted:
            return CuePermissionSectionPresentation(
                detail: "Grant Accessibility permission so Cue can paste automatically into the focused app.",
                primaryAction: .requestAccessibilityPermission,
                secondaryAction: .openAccessibilitySettings
            )
        case .granted:
            return CuePermissionSectionPresentation(
                detail: "Accessibility is ready. Cue can paste automatically.",
                primaryAction: nil,
                secondaryAction: nil
            )
        }
    }
}
