import Foundation

enum CuePermissionKind: Equatable {
    case microphone
    case accessibility

    var title: String {
        switch self {
        case .microphone:
            return "Microphone"
        case .accessibility:
            return "Accessibility"
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

enum CueAccessibilityPermissionState: Equatable {
    case granted
    case notGranted

    var isGranted: Bool {
        self == .granted
    }
}

struct CuePermissionSnapshot: Equatable {
    let microphone: CuePermissionState
    let accessibility: CueAccessibilityPermissionState

    var isMicrophoneReady: Bool {
        microphone.isGranted
    }

    var isAccessibilityReady: Bool {
        accessibility.isGranted
    }

    var canAutoPaste: Bool {
        accessibility.isGranted
    }

    var isFullyConfigured: Bool {
        isMicrophoneReady && isAccessibilityReady
    }

    var setupSummary: String {
        guard isMicrophoneReady else {
            return "Cue needs microphone access before dictation can run."
        }

        guard canAutoPaste else {
            return "Cue needs Accessibility permission to paste automatically."
        }

        return "Cue can record, transcribe, and paste automatically."
    }

    func resolves(_ error: CueError) -> Bool {
        switch error {
        case .microphonePermissionDenied:
            return isMicrophoneReady
        case .accessibilityPermissionDenied:
            return isAccessibilityReady
        default:
            return false
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
    let clipboardRestoreState: CueClipboardRestoreState
    /// Timestamp captured immediately after Command-V was posted, before the clipboard restore grace period.
    let pasteCommandPostedAt: Date
}

enum CueClipboardRestoreState: Equatable {
    case restored
    case skippedClipboardChanged
    case failed
}

enum CueInsertionDelivery: Equatable {
    case pasteCommandSent
}

struct LatencyMetrics: Equatable {
    let recordingDuration: TimeInterval
    let transcriptionDuration: TimeInterval
    let pasteDuration: TimeInterval
    let totalDuration: TimeInterval
    let modelLoadDuration: TimeInterval
    let backendPipelineDuration: TimeInterval

    /// Time from PTT key-down to first audible/visual ack (sound + icon change).
    let pressToAck: TimeInterval
    /// Time from PTT key-up to first sign Cue is working (stop sound + transcribing state).
    let releaseToProofOfLife: TimeInterval
    /// Time from PTT key-up to text inserted in target app. Excludes recording time.
    let releaseToInsert: TimeInterval
}

@MainActor
protocol SoundService {
    func playRecordingStarted()
    func playRecordingStopped()
    func playError()
}

enum CueError: LocalizedError, Equatable {
    case busy
    case microphonePermissionDenied
    case accessibilityPermissionDenied
    case missingMicrophoneInput
    case recordingFailed(String)
    case recordingAlreadyInProgress
    case noRecordingInProgress
    case recordingTooShort(actual: TimeInterval, minimum: TimeInterval)
    case modelDownloadFailed(String)
    case modelLoadFailed(String)
    case transcriptionFailed(String)
    case emptyTranscript
    case noFrontmostApplication
    case cannotPasteIntoCue
    case pasteFailed(String)

    var isPermissionRelated: Bool {
        switch self {
        case .microphonePermissionDenied, .accessibilityPermissionDenied:
            return true
        default:
            return false
        }
    }

    var isModelPreparationRelated: Bool {
        switch self {
        case .modelDownloadFailed, .modelLoadFailed:
            return true
        default:
            return false
        }
    }

    var shouldPlayErrorSound: Bool {
        switch self {
        case .missingMicrophoneInput, .recordingFailed, .transcriptionFailed, .pasteFailed:
            return true
        case .busy,
                .microphonePermissionDenied,
                .accessibilityPermissionDenied,
                .recordingAlreadyInProgress,
                .noRecordingInProgress,
                .recordingTooShort,
                .modelDownloadFailed,
                .modelLoadFailed,
                .emptyTranscript,
                .noFrontmostApplication,
                .cannotPasteIntoCue:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .busy:
            return "Cue is already handling another action."
        case .microphonePermissionDenied:
            return "Cue needs microphone access before it can record audio. Allow Cue in System Settings > Privacy & Security > Microphone."
        case .accessibilityPermissionDenied:
            return "Cue needs Accessibility permission to paste automatically. Allow Cue in System Settings > Privacy & Security > Accessibility."
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
        case .modelLoadFailed(let message):
            return "Cue could not load the base.en model: \(message)"
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

enum CueSessionState: Equatable {
    case idle
    case recording
    case transcribing
    case pasting
    case failed(CueFailure)

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
        case .failed:
            return "Error"
        }
    }

    var isBusy: Bool {
        switch self {
        case .recording, .transcribing, .pasting:
            return true
        case .idle, .failed:
            return false
        }
    }
}

struct CueFailure: Equatable {
    let cueError: CueError?
    let message: String

    static func from(_ error: Error) -> CueFailure {
        let cueError = error as? CueError
        let message: String

        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            message = description
        } else {
            message = error.localizedDescription
        }

        return CueFailure(cueError: cueError, message: message)
    }
}

struct CueSetupState: Equatable {
    var permissions: CuePermissionSnapshot
    var hasLoadedPermissions: Bool
    var modelStatus: ModelPreparationStatus
}

struct CueAppState: Equatable {
    var setup: CueSetupState
    var session: CueSessionState
    var transcript: String
    var lastInsertionResult: CueInsertionResult?
    var latencyMetrics: LatencyMetrics?

    static func initial(permissionSnapshot: CuePermissionSnapshot) -> CueAppState {
        CueAppState(
            setup: CueSetupState(
                permissions: permissionSnapshot,
                hasLoadedPermissions: true,
                modelStatus: .idle
            ),
            session: .idle,
            transcript: "",
            lastInsertionResult: nil,
            latencyMetrics: nil
        )
    }

    var currentFailure: CueFailure? {
        guard case .failed(let failure) = session else {
            return nil
        }

        return failure
    }

    var isReadyToRecord: Bool {
        setup.hasLoadedPermissions && setup.permissions.isFullyConfigured
    }

    var isModelReady: Bool {
        setup.modelStatus.isReady
    }
}

extension TimeInterval {
    var formattedSeconds: String {
        String(format: "%.2fs", self)
    }
}
