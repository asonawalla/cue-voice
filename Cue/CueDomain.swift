import Foundation

enum CuePhase: String, Equatable {
    case idle
    case recording
    case transcribing
    case pasting
    case error

    var title: String {
        switch self {
        case .idle:
            return "Idle"
        case .recording:
            return "Recording"
        case .transcribing:
            return "Transcribing"
        case .pasting:
            return "Pasting"
        case .error:
            return "Error"
        }
    }
}

enum CuePermissionKind: CaseIterable, Equatable {
    case microphone
    case paste

    var title: String {
        switch self {
        case .microphone:
            return "Microphone"
        case .paste:
            return "Accessibility"
        }
    }

    var requirementSummary: String {
        switch self {
        case .microphone:
            return "Cue needs microphone access to capture your speech."
        case .paste:
            return "Cue uses Accessibility to paste automatically into the focused app. After you enable it in System Settings, restart Cue to turn automatic paste on."
        }
    }

    var systemSettingsPath: String {
        switch self {
        case .microphone:
            return "System Settings > Privacy & Security > Microphone"
        case .paste:
            return "System Settings > Privacy & Security > Accessibility"
        }
    }
}

enum CuePermissionState: Equatable {
    case granted
    case notDetermined
    case denied

    var title: String {
        switch self {
        case .granted:
            return "Granted"
        case .notDetermined:
            return "Not Yet Granted"
        case .denied:
            return "Blocked"
        }
    }

    var isGranted: Bool {
        self == .granted
    }
}

enum CueAutomationPermissionState: Equatable {
    case available
    case unavailable

    var title: String {
        switch self {
        case .available:
            return "Ready"
        case .unavailable:
            return "Clipboard Mode"
        }
    }

    var isAvailable: Bool {
        self == .available
    }
}

struct CuePermissionSnapshot: Equatable {
    let microphone: CuePermissionState
    let paste: CueAutomationPermissionState

    var isMicrophoneReady: Bool {
        microphone.isGranted
    }

    var canAutoPaste: Bool {
        paste.isAvailable
    }

    var setupSummary: String {
        guard isMicrophoneReady else {
            return "Cue needs microphone access before dictation can run. Accessibility is optional and turns on automatic paste after Cue restarts."
        }

        guard canAutoPaste else {
            return "Cue can already record and transcribe. Enable Accessibility in System Settings, then restart Cue if you want automatic paste; until then Cue stays in clipboard mode."
        }

        return "Cue can record, transcribe, and paste automatically."
    }
}

enum ModelPreparationStatus: Equatable {
    case idle
    case checkingCache
    case downloading(progress: Double?)
    case loading
    case ready
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            return "Model not prepared"
        case .checkingCache:
            return "Checking local model cache"
        case .downloading(let progress):
            guard let progress else {
                return "Downloading base.en model"
            }
            return "Downloading base.en model (\(Int(progress * 100))%)"
        case .loading:
            return "Loading base.en model"
        case .ready:
            return "base.en model ready"
        case .failed(let message):
            return message
        }
    }

    var progressValue: Double? {
        guard case .downloading(let progress) = self else {
            return nil
        }

        return progress
    }

    var isPreparing: Bool {
        switch self {
        case .checkingCache, .downloading, .loading:
            return true
        case .idle, .ready, .failed:
            return false
        }
    }

    var isReady: Bool {
        if case .ready = self {
            return true
        }

        return false
    }
}

struct CueTranscriptionResult: Equatable {
    let text: String
    let language: String
    let recordingDuration: TimeInterval
    let modelLoadDuration: TimeInterval
    let pipelineDuration: TimeInterval
}

struct CueInsertionResult: Equatable {
    let delivery: CueInsertionDelivery
    let targetAppName: String?
    let targetBundleIdentifier: String?
    let pasteDuration: TimeInterval
    let clipboardRestoreOutcome: ClipboardRestoreOutcome
}

enum CueInsertionDelivery: Equatable {
    case pasteCommandSent
    case copiedToClipboard(CueClipboardFallbackReason)

    var title: String {
        switch self {
        case .pasteCommandSent:
            return "Paste Command Sent"
        case .copiedToClipboard:
            return "Copied to Clipboard"
        }
    }

    var detail: String {
        switch self {
        case .pasteCommandSent:
            return "Cue sent Command-V to the frontmost app and left the transcript on the clipboard in case manual paste is still needed."
        case .copiedToClipboard(let reason):
            return reason.description
        }
    }

    var usedAutomaticPaste: Bool {
        if case .pasteCommandSent = self {
            return true
        }

        return false
    }
}

enum CueClipboardFallbackReason: Equatable {
    case accessibilityPermissionMissing
    case noFrontmostApplication
    case targetWasCue
    case postEventSubmissionFailed(String)

    var description: String {
        switch self {
        case .accessibilityPermissionMissing:
            return "Automatic paste is unavailable. Cue copied the transcript to the clipboard for manual paste. If you just enabled Accessibility, restart Cue to turn automatic paste on."
        case .noFrontmostApplication:
            return "Cue could not determine a destination app, so it copied the transcript to the clipboard."
        case .targetWasCue:
            return "Cue was still frontmost, so it copied the transcript to the clipboard instead of pasting back into itself."
        case .postEventSubmissionFailed(let message):
            return "Automatic paste failed (\(message)). Cue left the transcript on the clipboard."
        }
    }
}

enum ClipboardRestoreOutcome: Equatable {
    case restored
    case skippedBecauseClipboardChanged
    case skippedBecauseSnapshotUnavailable
    case notNeededBecauseTranscriptStayedOnClipboard
    case failed(String)

    var title: String {
        switch self {
        case .restored:
            return "Previous clipboard restored"
        case .skippedBecauseClipboardChanged:
            return "Skipped restore because the clipboard changed"
        case .skippedBecauseSnapshotUnavailable:
            return "Skipped restore because Cue could not snapshot the clipboard"
        case .notNeededBecauseTranscriptStayedOnClipboard:
            return "Transcript left on the clipboard for manual paste"
        case .failed(let message):
            return "Cue could not restore the previous clipboard contents: \(message)"
        }
    }
}

struct LatencyMetrics: Equatable {
    let recordingDuration: TimeInterval
    let transcriptionDuration: TimeInterval
    let pasteDuration: TimeInterval
    let totalDuration: TimeInterval
    let modelLoadDuration: TimeInterval
    let backendPipelineDuration: TimeInterval
}

enum CueError: LocalizedError, Equatable {
    case busy
    case microphonePermissionDenied
    case missingMicrophoneInput
    case recordingFailed(String)
    case recordingAlreadyInProgress
    case noRecordingInProgress
    case recordingTooShort(actual: TimeInterval, minimum: TimeInterval)
    case modelDownloadFailed(String)
    case transcriptionFailed(String)
    case emptyTranscript
    case noFrontmostApplication
    case cannotPasteIntoCue
    case pasteFailed(String)

    var isPermissionRelated: Bool {
        switch self {
        case .microphonePermissionDenied:
            return true
        default:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .busy:
            return "Cue is already handling another action."
        case .microphonePermissionDenied:
            return "Cue needs microphone access before it can record audio. Allow Cue in System Settings > Privacy & Security > Microphone."
        case .missingMicrophoneInput:
            return "Cue could not find a usable microphone input device."
        case .recordingFailed(let message):
            return "Cue could not start recording: \(message)"
        case .recordingAlreadyInProgress:
            return "Recording is already in progress."
        case .noRecordingInProgress:
            return "There is no active recording to stop."
        case .recordingTooShort(let actual, let minimum):
            return "Recording was too short (\(actual.formattedSeconds)); hold for at least \(minimum.formattedSeconds)."
        case .modelDownloadFailed(let message):
            return "Cue could not prepare the base.en model: \(message)"
        case .transcriptionFailed(let message):
            return "Cue could not transcribe the recording: \(message)"
        case .emptyTranscript:
            return "Cue finished transcribing, but the result was empty."
        case .noFrontmostApplication:
            return "Cue could not determine which app should receive the paste."
        case .cannotPasteIntoCue:
            return "Cue can only paste into another app. Focus the destination app, then try again."
        case .pasteFailed(let message):
            return "Cue could not paste the transcript: \(message)"
        }
    }
}

extension TimeInterval {
    var formattedSeconds: String {
        String(format: "%.2fs", self)
    }
}
