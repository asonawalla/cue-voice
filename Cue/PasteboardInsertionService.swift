import AppKit
import CoreGraphics
import Foundation
import os

@MainActor
protocol TextInsertionService: AnyObject {
    func insert(_ text: String) async throws -> CueInsertionResult
}

struct CueRunningApplication: Equatable {
    let processIdentifier: pid_t
    let localizedName: String?
    let bundleIdentifier: String?
}

protocol FrontmostApplicationResolving {
    func frontmostApplication() -> CueRunningApplication?
}

protocol CuePasteboardWriting: AnyObject {
    func clearContents()
    func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool
}

protocol PasteCommandPosting {
    func postPasteCommand(to processIdentifier: pid_t) throws
}

@MainActor
final class PasteboardInsertionService: TextInsertionService {
    private let applicationResolver: FrontmostApplicationResolving
    private let pasteboard: CuePasteboardWriting
    private let pasteCommandPoster: PasteCommandPosting
    private let hasAccessibilityPermission: () -> Bool
    private let mainBundleIdentifier: String?
    private let logger = Logger(subsystem: "dev.sonawalla.Cue", category: "Insertion")

    init(
        applicationResolver: FrontmostApplicationResolving? = nil,
        pasteboard: CuePasteboardWriting? = nil,
        pasteCommandPoster: PasteCommandPosting? = nil,
        hasAccessibilityPermission: @escaping () -> Bool = { CGPreflightPostEventAccess() },
        mainBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.applicationResolver = applicationResolver ?? WorkspaceFrontmostApplicationResolver()
        self.pasteboard = pasteboard ?? SystemPasteboardWriter()
        self.pasteCommandPoster = pasteCommandPoster ?? CGEventPasteCommandPoster()
        self.hasAccessibilityPermission = hasAccessibilityPermission
        self.mainBundleIdentifier = mainBundleIdentifier
    }

    func insert(_ text: String) async throws -> CueInsertionResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CueError.emptyTranscript
        }

        let targetResolution = frontmostTargetApplication()

        switch targetResolution {
        case .fallback(let reason):
            return try copyTranscriptToClipboard(text, reason: reason, targetApplication: nil)
        case .target(let targetApplication):
            guard hasAccessibilityPermission() else {
                return try copyTranscriptToClipboard(
                    text,
                    reason: .accessibilityPermissionMissing,
                    targetApplication: targetApplication
                )
            }

            do {
                _ = try writeTranscriptToPasteboard(text)
            } catch {
                logger.error("Failed to write transcript to the pasteboard")
                throw error
            }

            let pasteStartedAt = Date()

            do {
                try pasteCommandPoster.postPasteCommand(to: targetApplication.processIdentifier)
            } catch {
                return try copyTranscriptToClipboard(
                    text,
                    reason: .postEventSubmissionFailed(error.localizedDescription),
                    targetApplication: targetApplication,
                    pasteStartedAt: pasteStartedAt
                )
            }

            let pasteDuration = Date().timeIntervalSince(pasteStartedAt)
            let targetAppName = targetApplication.localizedName ?? targetApplication.bundleIdentifier ?? "Unknown App"

            logger.info(
                "Sent paste command to \(targetAppName, privacy: .public) in \(pasteDuration, format: .fixed(precision: 2))s; transcript remains on clipboard"
            )

            return CueInsertionResult(
                delivery: .pasteCommandSent,
                targetAppName: targetAppName,
                targetBundleIdentifier: targetApplication.bundleIdentifier,
                pasteDuration: pasteDuration
            )
        }
    }

    private func copyTranscriptToClipboard(
        _ text: String,
        reason: CueClipboardFallbackReason,
        targetApplication: CueRunningApplication?,
        pasteStartedAt: Date? = nil
    ) throws -> CueInsertionResult {
        _ = try writeTranscriptToPasteboard(text)

        let pasteDuration = pasteStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let targetAppName = targetApplication?.localizedName ?? targetApplication?.bundleIdentifier

        logger.info(
            "Copied transcript to clipboard. reason=\(reason.description, privacy: .public) target=\(targetAppName ?? "none", privacy: .public)"
        )

        return CueInsertionResult(
            delivery: .copiedToClipboard(reason),
            targetAppName: targetAppName,
            targetBundleIdentifier: targetApplication?.bundleIdentifier,
            pasteDuration: pasteDuration
        )
    }

    private func frontmostTargetApplication() -> TargetApplicationResolution {
        guard let application = applicationResolver.frontmostApplication() else {
            return .fallback(.noFrontmostApplication)
        }

        if let mainBundleIdentifier, application.bundleIdentifier == mainBundleIdentifier {
            return .fallback(.targetWasCue)
        }

        guard application.localizedName != nil || application.bundleIdentifier != nil else {
            return .fallback(.noFrontmostApplication)
        }

        return .target(application)
    }

    private func writeTranscriptToPasteboard(_ text: String) throws -> Int {
        pasteboard.clearContents()

        guard pasteboard.setString(text, forType: .string) else {
            throw CueError.pasteFailed("Cue could not write plain text to the system pasteboard.")
        }

        return 0
    }
}

private enum TargetApplicationResolution {
    case target(CueRunningApplication)
    case fallback(CueClipboardFallbackReason)
}

private final class WorkspaceFrontmostApplicationResolver: FrontmostApplicationResolving {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func frontmostApplication() -> CueRunningApplication? {
        guard let application = workspace.frontmostApplication else {
            return nil
        }

        return CueRunningApplication(
            processIdentifier: application.processIdentifier,
            localizedName: application.localizedName,
            bundleIdentifier: application.bundleIdentifier
        )
    }
}

private final class SystemPasteboardWriter: CuePasteboardWriting {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func clearContents() {
        pasteboard.clearContents()
    }

    func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool {
        pasteboard.setString(string, forType: type)
    }
}

private final class CGEventPasteCommandPoster: PasteCommandPosting {
    func postPasteCommand(to processIdentifier: pid_t) throws {
        let commandKeyCode: CGKeyCode = 55
        let vKeyCode: CGKeyCode = 9

        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let commandDown = CGEvent(keyboardEventSource: source, virtualKey: commandKeyCode, keyDown: true),
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false),
            let commandUp = CGEvent(keyboardEventSource: source, virtualKey: commandKeyCode, keyDown: false)
        else {
            throw CueError.pasteFailed("Cue could not synthesize the Command-V keyboard events.")
        }

        commandDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        commandUp.flags = []

        commandDown.postToPid(processIdentifier)
        vDown.postToPid(processIdentifier)
        vUp.postToPid(processIdentifier)
        commandUp.postToPid(processIdentifier)
    }
}
