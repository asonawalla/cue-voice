import Foundation

enum CueCopy {
    static func permissionTitle(_ permission: CuePermissionKind) -> String {
        switch permission {
        case .microphone:
            return "Microphone"
        case .accessibility:
            return "Accessibility"
        }
    }

    static func permissionStateTitle(_ state: CuePermissionState) -> String {
        switch state {
        case .granted:
            return "Granted"
        case .notDetermined:
            return "Not Yet Granted"
        case .denied:
            return "Blocked"
        }
    }

    static func permissionSetupSummary(_ snapshot: CuePermissionSnapshot) -> String {
        guard snapshot.isMicrophoneReady else {
            return "Cue needs microphone access before dictation can run."
        }

        guard snapshot.canAutoPaste else {
            return "Cue needs Accessibility permission to paste automatically."
        }

        return "Cue can record, transcribe, and paste automatically."
    }

    static func modelPreparationStatusTitle(_ status: ModelPreparationStatus) -> String {
        let modelName = CueAppConfiguration.modelID

        switch status {
        case .idle:
            return "Model not prepared"
        case .checkingCache:
            return "Checking local model cache"
        case .downloading(let progress):
            guard let progress else {
                return "Downloading \(modelName) model"
            }
            return "Downloading \(modelName) model (\(Int(progress * 100))%)"
        case .loading:
            return "Loading \(modelName) model"
        case .ready:
            return "\(modelName) model ready"
        case .failed(let message):
            return message
        }
    }

    static func sessionTitle(_ state: CueSessionState) -> String {
        switch state {
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

    static func failureMessage(_ failure: CueFailure) -> String {
        if let cueError = failure.cueError {
            return errorMessage(for: cueError)
        }

        return failure.fallbackMessage
    }

    static func errorMessage(for error: Error) -> String {
        if let cueError = error as? CueError {
            return errorMessage(for: cueError)
        }

        return error.localizedDescription
    }

    static func errorMessage(for error: CueError) -> String {
        switch error {
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
            return "Cue could not prepare the \(CueAppConfiguration.modelID) model: \(message)"
        case .modelLoadFailed(let message):
            return "Cue could not load the \(CueAppConfiguration.modelID) model: \(message)"
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

private extension TimeInterval {
    var formattedSeconds: String {
        String(format: "%.2fs", self)
    }
}
