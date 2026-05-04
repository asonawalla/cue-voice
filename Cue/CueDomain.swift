import Foundation

enum CuePermissionKind: Equatable {
    case microphone
    case accessibility
}

enum CuePermissionState: Equatable {
    case granted
    case notDetermined
    case denied

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

enum ModelPreparationStatus: Equatable, Sendable {
    case idle
    case checkingCache
    case downloading(progress: Double?)
    case loading
    case ready
    case failed(String)

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

struct CueTranscriptionResult: Equatable, Sendable {
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

enum CueError: Error, Equatable, Sendable {
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

}

enum CueSessionState: Equatable {
    case idle
    case recording
    case transcribing
    case pasting
    case failed(CueFailure)

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
    let fallbackMessage: String

    static func from(_ error: Error) -> CueFailure {
        if let cueError = error as? CueError {
            return CueFailure(cueError: cueError, fallbackMessage: "")
        }

        return CueFailure(cueError: nil, fallbackMessage: error.localizedDescription)
    }
}

struct CueSetupState: Equatable {
    var permissions: CuePermissionSnapshot
    var hasLoadedPermissions: Bool
    var modelStatus: ModelPreparationStatus
}

enum CueAppEvent: Equatable {
    case permissionsRefreshed(CuePermissionSnapshot)
    case modelStatusChanged(ModelPreparationStatus)
    case modelPreparationSucceeded
    case dictationAttemptStarted
    case recordingStarted
    case transcriptionStarted
    case transcriptionCompleted(CueTranscriptionResult)
    case insertionCompleted(CueInsertionResult, LatencyMetrics)
    case failurePresented(CueFailure)
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

    mutating func apply(_ event: CueAppEvent) {
        switch event {
        case .permissionsRefreshed(let snapshot):
            setup.permissions = snapshot
            setup.hasLoadedPermissions = true

            if let cueError = currentFailure?.cueError, snapshot.resolves(cueError) {
                session = .idle
            }
        case .modelStatusChanged(let status):
            setup.modelStatus = status
        case .modelPreparationSucceeded:
            if currentFailure?.cueError?.isModelPreparationRelated == true {
                session = .idle
            }
        case .dictationAttemptStarted:
            latencyMetrics = nil

            if case .failed = session {
                session = .idle
            }
        case .recordingStarted:
            session = .recording
        case .transcriptionStarted:
            session = .transcribing
            latencyMetrics = nil
        case .transcriptionCompleted(let result):
            transcript = result.text
            session = .pasting
        case .insertionCompleted(let result, let metrics):
            lastInsertionResult = result
            latencyMetrics = metrics
            session = .idle
        case .failurePresented(let failure):
            session = .failed(failure)
        }
    }
}
