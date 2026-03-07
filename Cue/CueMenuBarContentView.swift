import AppKit
import SwiftUI

struct CueMenuBarContentView: View {
    @Bindable var model: CueAppModel
    @Bindable var hotkeyManager: CueHotkeyManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(action: {}) {
            Label(menuState.title, systemImage: model.menuBarSymbolName)
        }
        .disabled(true)

        Divider()

        ForEach(menuActions, id: \.self) { action in
            Button(action.title) {
                perform(action)
            }
        }
    }

    private var menuState: MenuState {
        guard model.hasLoadedPermissionSnapshot else {
            return .checkingSetup
        }

        switch model.permissionSnapshot.microphone {
        case .notDetermined:
            return .microphoneRequired
        case .denied:
            return .microphoneBlocked
        case .granted:
            break
        }

        switch model.phase {
        case .recording:
            return .recording
        case .transcribing:
            return .transcribing
        case .pasting:
            return .sendingTranscript
        case .error:
            return .actionFailed
        case .idle:
            if case .failed = model.modelStatus {
                return .actionFailed
            }

            guard model.isModelReady else {
                return .preparingModel
            }

            return model.permissionSnapshot.canAutoPaste ? .ready : .clipboardMode
        }
    }

    private var menuActions: [MenuAction] {
        switch menuState {
        case .checkingSetup, .preparingModel, .ready, .recording, .transcribing, .sendingTranscript:
            return [.openCue, .quitCue]
        case .microphoneRequired:
            return [.grantMicrophoneAccess, .openCue, .quitCue]
        case .microphoneBlocked:
            return [.openMicrophoneSettings, .openCue, .quitCue]
        case .clipboardMode:
            return [.openAccessibilitySettings, .restartCue, .openCue, .quitCue]
        case .actionFailed:
            if case .failed = model.modelStatus, model.shouldOfferModelRetry {
                return [.retryModelPreparation, .quitCue]
            }

            return [.openCue, .quitCue]
        }
    }

    private func perform(_ action: MenuAction) {
        switch action {
        case .grantMicrophoneAccess:
            Task {
                await model.requestMicrophonePermission()
            }
        case .openMicrophoneSettings:
            model.openMicrophoneSettings()
        case .openAccessibilitySettings:
            model.openAccessibilitySettings()
        case .restartCue:
            model.restartApplication()
        case .retryModelPreparation:
            Task {
                await model.retryModelPreparation()
            }
        case .openCue:
            openWindow(id: CueSceneID.mainWindow)
            NSApplication.shared.activate(ignoringOtherApps: true)
        case .quitCue:
            NSApplication.shared.terminate(nil)
        }
    }
}

private enum MenuState {
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
}

private enum MenuAction: Hashable {
    case grantMicrophoneAccess
    case openMicrophoneSettings
    case openAccessibilitySettings
    case restartCue
    case retryModelPreparation
    case openCue
    case quitCue

    var title: String {
        switch self {
        case .grantMicrophoneAccess:
            return "Grant Microphone Access"
        case .openMicrophoneSettings:
            return "Open Microphone Settings"
        case .openAccessibilitySettings:
            return "Open Accessibility Settings"
        case .restartCue:
            return "Restart Cue"
        case .retryModelPreparation:
            return "Retry Model Preparation"
        case .openCue:
            return "Open Cue"
        case .quitCue:
            return "Quit Cue"
        }
    }
}
