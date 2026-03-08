import Foundation

enum CueAppAction: Hashable {
    case requestMicrophonePermission
    case openMicrophoneSettings
    case openInputMonitoringSettings
    case openAccessibilitySettings
    case retryModelPreparation
    case openMainWindow
    case quit

    var title: String {
        switch self {
        case .requestMicrophonePermission:
            return "Grant Microphone Access"
        case .openMicrophoneSettings:
            return "Open Microphone Settings"
        case .openInputMonitoringSettings:
            return "Open Input Monitoring Settings"
        case .openAccessibilitySettings:
            return "Open Accessibility Settings"
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
}

struct CueSetupPresentation: Equatable {
    let statusSummary: String
    let microphone: CuePermissionSectionPresentation
    let inputMonitoring: CuePermissionSectionPresentation
    let accessibility: CuePermissionSectionPresentation
}

struct CueMenuPresentation: Equatable {
    let title: String
    let actions: [CueAppAction]
}

struct CueAppPresentation: Equatable {
    let needsPermissionPrompt: Bool
    let shouldOfferModelRetry: Bool
    let menuBarSymbolName: String
    let menuBarPrimaryStatus: String
    let menuBarSecondaryStatus: String?
    let menu: CueMenuPresentation
    let setup: CueSetupPresentation

    init(state: CueAppState) {
        let hasLoadedPermissions = state.setup.hasLoadedPermissions
        let permissions = state.setup.permissions

        needsPermissionPrompt = hasLoadedPermissions && !permissions.isFullyReady
        shouldOfferModelRetry = state.isReadyToRecord && !state.isModelReady && !state.setup.modelStatus.isPreparing

        menuBarSymbolName = CueAppPresentation.makeMenuBarSymbolName(state: state)
        menuBarPrimaryStatus = CueAppPresentation.makeMenuBarPrimaryStatus(state: state)
        menuBarSecondaryStatus = CueAppPresentation.makeMenuBarSecondaryStatus(state: state)

        let menuState = CueMenuState(state: state, shouldOfferModelRetry: shouldOfferModelRetry)
        menu = CueMenuPresentation(title: menuState.title, actions: menuState.actions)

        setup = CueSetupPresentation(
            statusSummary: permissions.setupSummary,
            microphone: CueAppPresentation.makeMicrophonePresentation(for: permissions.microphone),
            inputMonitoring: CueAppPresentation.makeInputMonitoringPresentation(for: permissions.inputMonitoring),
            accessibility: CueAppPresentation.makeAccessibilityPresentation(for: permissions.accessibility)
        )
    }

    private static func makeMenuBarSymbolName(state: CueAppState) -> String {
        guard state.setup.hasLoadedPermissions else {
            return "waveform.circle"
        }

        guard state.setup.permissions.isFullyReady else {
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

        guard state.setup.permissions.isFullyReady else {
            return menuTitleForMissingPermissions(state.setup.permissions)
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

        guard state.setup.permissions.isFullyReady else {
            return state.setup.permissions.setupSummary
        }

        switch state.session {
        case .recording:
            return "Release the modifier to stop recording."
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

            return "Hold the selected modifier in any app."
        }
    }

    private static func makeMicrophonePresentation(for permission: CuePermissionState) -> CuePermissionSectionPresentation {
        switch permission {
        case .notDetermined:
            return CuePermissionSectionPresentation(
                detail: "Grant microphone access so Cue can capture your speech.",
                primaryAction: .requestMicrophonePermission
            )
        case .denied:
            return CuePermissionSectionPresentation(
                detail: "Microphone access is blocked. Open System Settings to allow Cue to record.",
                primaryAction: .openMicrophoneSettings
            )
        case .granted:
            return CuePermissionSectionPresentation(
                detail: "Microphone is ready.",
                primaryAction: nil
            )
        }
    }

    private static func makeInputMonitoringPresentation(for permission: CueSystemPermissionState) -> CuePermissionSectionPresentation {
        switch permission {
        case .granted:
            return CuePermissionSectionPresentation(
                detail: "Input Monitoring is ready. Cue can listen for the selected push-to-talk modifier globally.",
                primaryAction: nil
            )
        case .unavailable:
            return CuePermissionSectionPresentation(
                detail: "Enable Input Monitoring so Cue can start and stop recording when you hold the selected modifier in any app.",
                primaryAction: .openInputMonitoringSettings
            )
        }
    }

    private static func makeAccessibilityPresentation(for permission: CueSystemPermissionState) -> CuePermissionSectionPresentation {
        switch permission {
        case .granted:
            return CuePermissionSectionPresentation(
                detail: "Accessibility is ready. Cue can paste transcripts into the focused app after recording.",
                primaryAction: nil
            )
        case .unavailable:
            return CuePermissionSectionPresentation(
                detail: "Enable Accessibility so Cue can send the transcript into the focused app after recording finishes.",
                primaryAction: .openAccessibilitySettings
            )
        }
    }

    fileprivate static func menuTitleForMissingPermissions(_ permissions: CuePermissionSnapshot) -> String {
        if permissions.missingPermissions == [.microphone] {
            return "Microphone Required"
        }

        if permissions.missingPermissions == [.inputMonitoring] {
            return "Input Monitoring Required"
        }

        if permissions.missingPermissions == [.accessibility] {
            return "Accessibility Required"
        }

        return "Setup Required"
    }
}

private enum CueMenuState {
    case checkingSetup
    case setupRequired(title: String, actions: [CueAppAction])
    case preparingModel
    case ready
    case recording
    case transcribing
    case sendingTranscript
    case actionFailed(shouldOfferModelRetry: Bool)

    init(state: CueAppState, shouldOfferModelRetry: Bool) {
        guard state.setup.hasLoadedPermissions else {
            self = .checkingSetup
            return
        }

        guard state.setup.permissions.isFullyReady else {
            self = .setupRequired(
                title: CueAppPresentation.menuTitleForMissingPermissions(state.setup.permissions),
                actions: Self.setupActions(for: state.setup.permissions)
            )
            return
        }

        switch state.session {
        case .recording:
            self = .recording
        case .transcribing:
            self = .transcribing
        case .pasting:
            self = .sendingTranscript
        case .failed:
            self = .actionFailed(shouldOfferModelRetry: shouldOfferModelRetry)
        case .idle:
            if case .failed = state.setup.modelStatus {
                self = .actionFailed(shouldOfferModelRetry: shouldOfferModelRetry)
            } else if !state.isModelReady {
                self = .preparingModel
            } else {
                self = .ready
            }
        }
    }

    var title: String {
        switch self {
        case .checkingSetup:
            return "Checking Setup"
        case .setupRequired(let title, _):
            return title
        case .preparingModel:
            return "Preparing Model"
        case .ready:
            return "Ready"
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
        case .setupRequired(_, let actions):
            return actions
        case .actionFailed(let shouldOfferModelRetry):
            return shouldOfferModelRetry ? [.retryModelPreparation, .openMainWindow, .quit] : [.openMainWindow, .quit]
        }
    }

    private static func setupActions(for permissions: CuePermissionSnapshot) -> [CueAppAction] {
        var actions: [CueAppAction] = []

        if !permissions.isMicrophoneReady {
            let microphoneAction: CueAppAction = permissions.microphone == .notDetermined
                ? .requestMicrophonePermission
                : .openMicrophoneSettings
            actions.append(microphoneAction)
        }

        if !permissions.canMonitorInput {
            actions.append(.openInputMonitoringSettings)
        }

        if !permissions.canAutoPaste {
            actions.append(.openAccessibilitySettings)
        }

        actions.append(.openMainWindow)
        actions.append(.quit)

        return actions
    }
}
