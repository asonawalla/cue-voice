import AppKit
import AVFAudio
import CoreGraphics
import Foundation
import os

@MainActor
protocol PermissionService: AnyObject {
    func currentPermissionSnapshot() -> CuePermissionSnapshot
    func requestMicrophonePermission() async -> CuePermissionState
    func requestInputMonitoringPermission()
    func requestAccessibilityPermission()
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
            inputMonitoring: inputMonitoringPermissionState,
            accessibility: accessibilityPermissionState
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

    func requestAccessibilityPermission() {
        let granted = CGRequestPostEventAccess()
        logger.info("Requested Accessibility/Post Event access; current grant state is \(granted, privacy: .public)")
    }

    func requestInputMonitoringPermission() {
        let granted = CGRequestListenEventAccess()
        logger.info("Requested Input Monitoring access; current grant state is \(granted, privacy: .public)")
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

    private var inputMonitoringPermissionState: CueSystemPermissionState {
        CGPreflightListenEventAccess() ? .granted : .unavailable
    }

    private var accessibilityPermissionState: CueSystemPermissionState {
        CGPreflightPostEventAccess() ? .granted : .unavailable
    }
}

private extension CuePermissionKind {
    var settingsURL: URL? {
        switch self {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .inputMonitoring:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }
}
