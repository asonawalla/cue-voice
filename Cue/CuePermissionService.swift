import AppKit
import AVFAudio
import CoreGraphics
import Foundation
import os

@MainActor
protocol PermissionService: AnyObject {
    func currentPermissionSnapshot() -> CuePermissionSnapshot
    func requestMicrophonePermission() async -> CuePermissionState
    func requestPastePermission() async -> CueAutomationPermissionState
    func openSystemSettings(for permission: CuePermissionKind)
}

@MainActor
final class SystemPermissionService: PermissionService {
    private let workspace: NSWorkspace
    private let logger = Logger(subsystem: "dev.sonawalla.Cue", category: "Permissions")

    init(
        workspace: NSWorkspace = .shared
    ) {
        self.workspace = workspace
    }

    func currentPermissionSnapshot() -> CuePermissionSnapshot {
        CuePermissionSnapshot(
            microphone: microphonePermissionState,
            paste: pastePermissionState
        )
    }

    func requestMicrophonePermission() async -> CuePermissionState {
        _ = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        let currentState = microphonePermissionState
        logger.info("Microphone permission result: \(currentState.title, privacy: .public)")
        return currentState
    }

    func requestPastePermission() async -> CueAutomationPermissionState {
        let granted = CGRequestPostEventAccess()
        let currentState = granted ? CueAutomationPermissionState.available : pastePermissionState

        logger.info("Paste permission result: \(currentState.title, privacy: .public)")
        return currentState
    }

    func openSystemSettings(for permission: CuePermissionKind) {
        let openedDirectPane = permission.settingsURL.flatMap(workspace.open) ?? false

        if openedDirectPane {
            logger.info("Opened System Settings for \(permission.title, privacy: .public)")
            return
        }

        let fallbackURL = URL(fileURLWithPath: "/System/Applications/System Settings.app", isDirectory: true)
        if workspace.open(fallbackURL) {
            logger.info("Opened System Settings app fallback for \(permission.title, privacy: .public)")
            return
        }

        logger.error("Failed to open System Settings for \(permission.title, privacy: .public)")
    }

    private var microphonePermissionState: CuePermissionState {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return .granted
        case .undetermined:
            return .notDetermined
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }

    private var pastePermissionState: CueAutomationPermissionState {
        CGPreflightPostEventAccess() ? .available : .unavailable
    }
}

private extension CuePermissionKind {
    var settingsURL: URL? {
        switch self {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .paste:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }
}
