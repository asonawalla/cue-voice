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

struct CuePermissionSnapshot {
    let microphone: CuePermissionState
    let accessibility: CueAccessibilityPermissionState

    var isMicrophoneReady: Bool {
        microphone.isGranted
    }

    var isAccessibilityReady: Bool {
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
    case failed

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

struct CueInsertionResult {
    let pasteDuration: TimeInterval
    /// Timestamp captured immediately after Command-V was posted, before the clipboard restore grace period.
    let pasteCommandPostedAt: Date
}

struct LatencyMetrics {
    let transcriptionDuration: TimeInterval
    let pasteDuration: TimeInterval
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
    case unexpected(String)

    var shouldPlayErrorSound: Bool {
        switch self {
        case .missingMicrophoneInput, .recordingFailed, .transcriptionFailed, .pasteFailed:
            return true
        case .microphonePermissionDenied,
                .accessibilityPermissionDenied,
                .recordingAlreadyInProgress,
                .noRecordingInProgress,
                .recordingTooShort,
                .modelDownloadFailed,
                .modelLoadFailed,
                .emptyTranscript,
                .noFrontmostApplication,
                .cannotPasteIntoCue,
                .unexpected:
            return false
        }
    }

}

enum CueSessionState: Equatable {
    case idle
    case recording
    case transcribing
    case pasting
    case failed(CueError)

    var isBusy: Bool {
        switch self {
        case .recording, .transcribing, .pasting:
            return true
        case .idle, .failed:
            return false
        }
    }
}

struct CueAppState {
    var permissions: CuePermissionSnapshot
    var modelStatus: ModelPreparationStatus = .idle
    var session: CueSessionState = .idle
    var recordingPreviewText = ""
    var isRecordingPreviewUnavailable = false
    var latencyMetrics: LatencyMetrics? = nil

    var currentFailure: CueError? {
        guard case .failed(let error) = session else {
            return nil
        }

        return error
    }

}
