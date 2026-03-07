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
            return "Cue needs Accessibility access to send Command-V into other apps."
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

struct CuePermissionSnapshot: Equatable {
    let microphone: CuePermissionState
    let paste: CuePermissionState

    var isReadyForUse: Bool {
        microphone.isGranted && paste.isGranted
    }

    var blockedPermissions: [CuePermissionKind] {
        CuePermissionKind.allCases.filter { !state(for: $0).isGranted }
    }

    var setupSummary: String {
        let blockedTitles = blockedPermissions.map(\.title)

        switch blockedTitles.count {
        case 0:
            return "Cue has the permissions it needs."
        case 1:
            return "Cue needs \(blockedTitles[0]) access before push-to-talk can run."
        case 2:
            return "Cue needs Microphone and Accessibility access before push-to-talk can run."
        default:
            return "Cue needs additional permissions before push-to-talk can run."
        }
    }

    func state(for permission: CuePermissionKind) -> CuePermissionState {
        switch permission {
        case .microphone:
            return microphone
        case .paste:
            return paste
        }
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
    let targetAppName: String
    let targetBundleIdentifier: String?
    let pasteDuration: TimeInterval
    let clipboardRestoreOutcome: ClipboardRestoreOutcome
}

enum ClipboardRestoreOutcome: Equatable {
    case restored
    case skippedBecauseClipboardChanged
    case skippedBecauseSnapshotUnavailable
    case failed(String)

    var title: String {
        switch self {
        case .restored:
            return "Previous clipboard restored"
        case .skippedBecauseClipboardChanged:
            return "Skipped restore because the clipboard changed"
        case .skippedBecauseSnapshotUnavailable:
            return "Skipped restore because Cue could not snapshot the clipboard"
        case .failed(let message):
            return "Paste succeeded, but clipboard restore failed: \(message)"
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
    case pastePermissionDenied
    case noFrontmostApplication
    case cannotPasteIntoCue
    case pasteFailed(String)

    var isPermissionRelated: Bool {
        switch self {
        case .microphonePermissionDenied, .pastePermissionDenied:
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
        case .pastePermissionDenied:
            return "Cue needs Accessibility permission to paste into other apps. Allow Cue in System Settings > Privacy & Security > Accessibility. If you just enabled it, relaunch Cue before trying again."
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
