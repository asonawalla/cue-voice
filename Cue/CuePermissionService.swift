import AppKit
import AVFAudio
import CoreGraphics
import Foundation
import os

@MainActor
protocol PermissionService: AnyObject {
    func currentPermissionSnapshot() -> CuePermissionSnapshot
    func requestMicrophonePermission() async
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
            accessibility: accessibilityPermissionState
        )
    }

    func requestMicrophonePermission() async {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { _ in
                continuation.resume()
            }
        }

        let currentState = microphonePermissionState
        logger.info("Microphone permission result: \(CueCopy.permissionStateTitle(currentState), privacy: .public)")
    }

    func requestAccessibilityPermission() {
        let granted = CGRequestPostEventAccess()
        logger.info("Requested automatic paste access; current grant state is \(granted, privacy: .public)")
    }

    func openSystemSettings(for permission: CuePermissionKind) {
        let openedDirectPane = permission.settingsURL.flatMap(workspace.open) ?? false

        if openedDirectPane {
            logger.info("Opened System Settings for \(CueCopy.permissionTitle(permission), privacy: .public)")
            return
        }

        let fallbackURL = URL(fileURLWithPath: "/System/Applications/System Settings.app", isDirectory: true)
        if workspace.open(fallbackURL) {
            logger.info("Opened System Settings app fallback for \(CueCopy.permissionTitle(permission), privacy: .public)")
            return
        }

        logger.error("Failed to open System Settings for \(CueCopy.permissionTitle(permission), privacy: .public)")
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

    private var accessibilityPermissionState: CueAccessibilityPermissionState {
        CGPreflightPostEventAccess() ? .granted : .notGranted
    }
}

private extension CuePermissionKind {
    var settingsURL: URL? {
        switch self {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }
}
