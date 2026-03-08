import Foundation

enum CuePermissionKind: CaseIterable, Equatable {
    case microphone
    case inputMonitoring
    case accessibility

    var title: String {
        switch self {
        case .microphone:
            return "Microphone"
        case .inputMonitoring:
            return "Input Monitoring"
        case .accessibility:
            return "Accessibility"
        }
    }

    var requirementSummary: String {
        switch self {
        case .microphone:
            return "Cue needs microphone access to capture your speech."
        case .inputMonitoring:
            return "Cue needs Input Monitoring so it can listen for your push-to-talk modifier in any app."
        case .accessibility:
            return "Cue needs Accessibility so it can paste the transcript into the focused app when recording finishes."
        }
    }

    var systemSettingsPath: String {
        switch self {
        case .microphone:
            return "System Settings > Privacy & Security > Microphone"
        case .inputMonitoring:
            return "System Settings > Privacy & Security > Input Monitoring"
        case .accessibility:
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

enum CueSystemPermissionState: Equatable {
    case granted
    case unavailable

    var title: String {
        switch self {
        case .granted:
            return "Granted"
        case .unavailable:
            return "Not Ready"
        }
    }

    var isGranted: Bool {
        self == .granted
    }
}

struct CuePermissionSnapshot: Equatable {
    let microphone: CuePermissionState
    let inputMonitoring: CueSystemPermissionState
    let accessibility: CueSystemPermissionState

    var isMicrophoneReady: Bool {
        microphone.isGranted
    }

    var canMonitorInput: Bool {
        inputMonitoring.isGranted
    }

    var canAutoPaste: Bool {
        accessibility.isGranted
    }

    var isFullyReady: Bool {
        isMicrophoneReady && canMonitorInput && canAutoPaste
    }

    var missingPermissions: [CuePermissionKind] {
        var permissions: [CuePermissionKind] = []

        if !isMicrophoneReady {
            permissions.append(.microphone)
        }

        if !canMonitorInput {
            permissions.append(.inputMonitoring)
        }

        if !canAutoPaste {
            permissions.append(.accessibility)
        }

        return permissions
    }

    var primaryBlockingPermission: CuePermissionKind? {
        missingPermissions.first
    }

    var setupSummary: String {
        guard !isFullyReady else {
            return "Cue is ready to listen, transcribe, and paste automatically."
        }

        if missingPermissions == [.microphone] {
            return "Cue needs microphone access before push-to-talk can run."
        }

        if missingPermissions == [.inputMonitoring] {
            return "Cue needs Input Monitoring before it can listen for the selected push-to-talk modifier globally."
        }

        if missingPermissions == [.accessibility] {
            return "Cue needs Accessibility before it can paste transcripts into the focused app."
        }

        return "Cue needs microphone, Input Monitoring, and Accessibility before push-to-talk can run."
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
            return "Automatic paste is unavailable. Cue copied the transcript to the clipboard for manual paste."
        case .noFrontmostApplication:
            return "Cue could not determine a destination app, so it copied the transcript to the clipboard."
        case .targetWasCue:
            return "Cue was still frontmost, so it copied the transcript to the clipboard instead of pasting back into itself."
        case .postEventSubmissionFailed(let message):
            return "Automatic paste failed (\(message)). Cue left the transcript on the clipboard."
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
    case inputMonitoringPermissionDenied
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
        case .microphonePermissionDenied, .inputMonitoringPermissionDenied, .accessibilityPermissionDenied:
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

    var errorDescription: String? {
        switch self {
        case .busy:
            return "Cue is already handling another action."
        case .microphonePermissionDenied:
            return "Cue needs microphone access before it can record audio. Allow Cue in System Settings > Privacy & Security > Microphone."
        case .inputMonitoringPermissionDenied:
            return "Cue needs Input Monitoring before it can listen for the selected push-to-talk modifier. Allow Cue in System Settings > Privacy & Security > Input Monitoring."
        case .accessibilityPermissionDenied:
            return "Cue needs Accessibility before it can paste transcripts into the focused app. Allow Cue in System Settings > Privacy & Security > Accessibility."
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

    var isPermissionRelated: Bool {
        cueError?.isPermissionRelated ?? false
    }

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
        setup.hasLoadedPermissions && setup.permissions.isFullyReady
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
