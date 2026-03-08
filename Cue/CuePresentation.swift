import Foundation

enum CueAppAction: Hashable {
    case requestMicrophonePermission
    case openMicrophoneSettings
    case openAccessibilitySettings
    case restartApplication
    case retryModelPreparation
    case openMainWindow
    case quit

    var title: String {
        switch self {
        case .requestMicrophonePermission:
            return "Grant Microphone Access"
        case .openMicrophoneSettings:
            return "Open Microphone Settings"
        case .openAccessibilitySettings:
            return "Open Accessibility Settings"
        case .restartApplication:
            return "Restart Cue"
        case .retryModelPreparation:
            return "Retry Model Preparation"
        case .openMainWindow:
            return "Open Cue"
        case .quit:
            return "Quit Cue"
        }
    }
}

struct CuePermissionSectionPresentation: Equatable {
    let detail: String
    let primaryAction: CueAppAction?
    let secondaryAction: CueAppAction?
    let showsClipboardModeDismissal: Bool
}

struct CueSetupPresentation: Equatable {
    let statusSummary: String
    let microphone: CuePermissionSectionPresentation
    let accessibility: CuePermissionSectionPresentation
    let automaticPasteWarningMessage: String?
    let accessibilityRestartMessage: String?
}

struct CueMenuPresentation: Equatable {
    let title: String
    let actions: [CueAppAction]
}

struct CueAppPresentation: Equatable {
    let needsPermissionPrompt: Bool
    let shouldOfferModelRetry: Bool
    let showsAutomaticPasteIndicator: Bool
    let menuBarSymbolName: String
    let menuBarPrimaryStatus: String
    let menuBarSecondaryStatus: String?
    let menu: CueMenuPresentation
    let setup: CueSetupPresentation

    init(state: CueAppState) {
        let hasLoadedPermissions = state.setup.hasLoadedPermissions
        let permissions = state.setup.permissions
        let automaticPasteWarningMessage = hasLoadedPermissions && permissions.isMicrophoneReady && !permissions.canAutoPaste
            ? "Automatic paste is off. Cue will copy transcripts to the clipboard until Accessibility is enabled and Cue restarts."
            : nil
        let accessibilityRestartMessage = hasLoadedPermissions && permissions.isMicrophoneReady && !permissions.canAutoPaste
            ? "After you enable Cue in Accessibility settings, restart the app to turn automatic paste on."
            : nil

        needsPermissionPrompt = hasLoadedPermissions && (!permissions.isMicrophoneReady || !permissions.canAutoPaste)
        shouldOfferModelRetry = state.isReadyToRecord && !state.isModelReady && !state.setup.modelStatus.isPreparing
        showsAutomaticPasteIndicator = hasLoadedPermissions && permissions.isMicrophoneReady && !permissions.canAutoPaste

        menuBarSymbolName = CueAppPresentation.makeMenuBarSymbolName(state: state)
        menuBarPrimaryStatus = CueAppPresentation.makeMenuBarPrimaryStatus(state: state)
        menuBarSecondaryStatus = CueAppPresentation.makeMenuBarSecondaryStatus(
            state: state,
            automaticPasteWarningMessage: automaticPasteWarningMessage
        )

        let menuState = CueMenuState(state: state, shouldOfferModelRetry: shouldOfferModelRetry)
        menu = CueMenuPresentation(title: menuState.title, actions: menuState.actions)

        setup = CueSetupPresentation(
            statusSummary: permissions.setupSummary,
            microphone: CueAppPresentation.makeMicrophonePresentation(for: permissions.microphone),
            accessibility: CueAppPresentation.makeAccessibilityPresentation(
                permissions: permissions,
                accessibilityRestartMessage: accessibilityRestartMessage
            ),
            automaticPasteWarningMessage: automaticPasteWarningMessage,
            accessibilityRestartMessage: accessibilityRestartMessage
        )
    }

    private static func makeMenuBarSymbolName(state: CueAppState) -> String {
        guard state.setup.hasLoadedPermissions else {
            return "waveform.circle"
        }

        guard state.setup.permissions.isMicrophoneReady else {
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

        switch state.session {
        case .idle:
            guard state.isModelReady else {
                return "Preparing Model"
            }

            return state.setup.permissions.canAutoPaste ? "Ready" : "Clipboard Mode"
        default:
            return state.session.title
        }
    }

    private static func makeMenuBarSecondaryStatus(
        state: CueAppState,
        automaticPasteWarningMessage: String?
    ) -> String? {
        guard state.setup.hasLoadedPermissions else {
            return "Cue is checking which permissions are available."
        }

        guard state.setup.permissions.isMicrophoneReady else {
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

            return automaticPasteWarningMessage ?? "Hold the push-to-talk shortcut in any app."
        }
    }

    private static func makeMicrophonePresentation(for permission: CuePermissionState) -> CuePermissionSectionPresentation {
        switch permission {
        case .notDetermined:
            return CuePermissionSectionPresentation(
                detail: "Grant microphone access first so Cue can start recording.",
                primaryAction: .requestMicrophonePermission,
                secondaryAction: nil,
                showsClipboardModeDismissal: false
            )
        case .denied:
            return CuePermissionSectionPresentation(
                detail: "Microphone access is blocked. Open System Settings to allow Cue to record.",
                primaryAction: .openMicrophoneSettings,
                secondaryAction: nil,
                showsClipboardModeDismissal: false
            )
        case .granted:
            return CuePermissionSectionPresentation(
                detail: "Microphone is ready. Cue can record on this launch.",
                primaryAction: nil,
                secondaryAction: nil,
                showsClipboardModeDismissal: false
            )
        }
    }

    private static func makeAccessibilityPresentation(
        permissions: CuePermissionSnapshot,
        accessibilityRestartMessage: String?
    ) -> CuePermissionSectionPresentation {
        guard permissions.isMicrophoneReady else {
            return CuePermissionSectionPresentation(
                detail: "Finish microphone setup first. Then you can optionally enable Accessibility for automatic paste.",
                primaryAction: nil,
                secondaryAction: nil,
                showsClipboardModeDismissal: false
            )
        }

        guard !permissions.canAutoPaste else {
            return CuePermissionSectionPresentation(
                detail: "Accessibility is ready on this launch. Cue can paste automatically into the focused app.",
                primaryAction: nil,
                secondaryAction: nil,
                showsClipboardModeDismissal: false
            )
        }

        return CuePermissionSectionPresentation(
            detail: accessibilityRestartMessage ?? "Open Accessibility settings, enable Cue, then restart the app to turn automatic paste on.",
            primaryAction: .openAccessibilitySettings,
            secondaryAction: .restartApplication,
            showsClipboardModeDismissal: true
        )
    }
}

private enum CueMenuState {
    case checkingSetup
    case microphoneRequired
    case microphoneBlocked
    case preparingModel
    case ready
    case clipboardMode
    case recording
    case transcribing
    case sendingTranscript
    case actionFailed

    init(state: CueAppState, shouldOfferModelRetry: Bool) {
        guard state.setup.hasLoadedPermissions else {
            self = .checkingSetup
            return
        }

        switch state.setup.permissions.microphone {
        case .notDetermined:
            self = .microphoneRequired
        case .denied:
            self = .microphoneBlocked
        case .granted:
            switch state.session {
            case .recording:
                self = .recording
            case .transcribing:
                self = .transcribing
            case .pasting:
                self = .sendingTranscript
            case .failed:
                self = .actionFailed
            case .idle:
                if case .failed = state.setup.modelStatus {
                    self = .actionFailed
                } else if !state.isModelReady {
                    self = .preparingModel
                } else {
                    self = state.setup.permissions.canAutoPaste ? .ready : .clipboardMode
                }
            }
        }
    }

    var title: String {
        switch self {
        case .checkingSetup:
            return "Checking Setup"
        case .microphoneRequired:
            return "Microphone Required"
        case .microphoneBlocked:
            return "Microphone Blocked"
        case .preparingModel:
            return "Preparing Model"
        case .ready:
            return "Ready"
        case .clipboardMode:
            return "Clipboard Mode"
        case .recording:
            return "Recording"
        case .transcribing:
            return "Transcribing"
        case .sendingTranscript:
            return "Sending Transcript"
        case .actionFailed:
            return "Action Failed"
        }
    }

    var actions: [CueAppAction] {
        switch self {
        case .checkingSetup, .preparingModel, .ready, .recording, .transcribing, .sendingTranscript:
            return [.openMainWindow, .quit]
        case .microphoneRequired:
            return [.requestMicrophonePermission, .openMainWindow, .quit]
        case .microphoneBlocked:
            return [.openMicrophoneSettings, .openMainWindow, .quit]
        case .clipboardMode:
            return [.openAccessibilitySettings, .restartApplication, .openMainWindow, .quit]
        case .actionFailed:
            return [.retryModelPreparation, .quit]
        }
    }
}
