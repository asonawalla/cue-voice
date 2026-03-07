import AppKit
import AVFAudio
import CoreGraphics
import Foundation
import os

@MainActor
protocol PermissionService: AnyObject {
    func currentPermissionSnapshot() -> CuePermissionSnapshot
    func requestMicrophonePermission() async -> CuePermissionState
    func requestPastePermission() async -> CuePermissionState
    func openSystemSettings(for permission: CuePermissionKind)
}

@MainActor
final class SystemPermissionService: PermissionService {
    private let workspace: NSWorkspace
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "dev.sonawalla.Cue", category: "Permissions")

    private static let pastePermissionRequestedKey = "Cue.pastePermissionRequested"

    init(
        workspace: NSWorkspace = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.workspace = workspace
        self.defaults = defaults
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

    func requestPastePermission() async -> CuePermissionState {
        defaults.set(true, forKey: Self.pastePermissionRequestedKey)
        let granted = CGRequestPostEventAccess()
        let currentState = granted ? CuePermissionState.granted : pastePermissionState

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

    private var pastePermissionState: CuePermissionState {
        if CGPreflightPostEventAccess() {
            return .granted
        }

        return defaults.bool(forKey: Self.pastePermissionRequestedKey) ? .denied : .notDetermined
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
