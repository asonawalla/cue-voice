import AppKit
import CoreGraphics
import Foundation
import os

@MainActor
protocol TextInsertionService: AnyObject {
    func insert(_ text: String) async throws -> CueInsertionResult
}

@MainActor
final class PasteboardInsertionService: TextInsertionService {
    private let workspace: NSWorkspace
    private let pasteboard: NSPasteboard
    private let mainBundleIdentifier: String?
    private let logger = Logger(subsystem: "dev.sonawalla.Cue", category: "Insertion")

    init(
        workspace: NSWorkspace = .shared,
        pasteboard: NSPasteboard = .general,
        mainBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.workspace = workspace
        self.pasteboard = pasteboard
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
            guard hasPostEventAccess() else {
                return try copyTranscriptToClipboard(
                    text,
                    reason: .accessibilityPermissionMissing,
                    targetApplication: targetApplication
                )
            }

            let snapshot = PasteboardSnapshot.capture(from: pasteboard)
            let cueWriteChangeCount: Int

            do {
                cueWriteChangeCount = try writeTranscriptToPasteboard(text)
            } catch {
                _ = restoreSnapshotImmediatelyIfAvailable(snapshot)
                logger.error("Failed to write transcript to the pasteboard")
                throw error
            }

            let pasteStartedAt = Date()

            do {
                try postPasteCommand(to: targetApplication.processIdentifier)
            } catch {
                return try copyTranscriptToClipboard(
                    text,
                    reason: .postEventSubmissionFailed(error.localizedDescription),
                    targetApplication: targetApplication,
                    pasteStartedAt: pasteStartedAt
                )
            }

            let restoreOutcome = await restorePasteboardIfNeeded(
                snapshot,
                expectedCueChangeCount: cueWriteChangeCount
            )
            let pasteDuration = Date().timeIntervalSince(pasteStartedAt)
            let targetAppName = targetApplication.localizedName ?? targetApplication.bundleIdentifier ?? "Unknown App"

            logger.info(
                "Pasted transcript into \(targetAppName, privacy: .public) in \(pasteDuration, format: .fixed(precision: 2))s; restore=\(restoreOutcome.title, privacy: .public)"
            )

            return CueInsertionResult(
                delivery: .pasted,
                targetAppName: targetAppName,
                targetBundleIdentifier: targetApplication.bundleIdentifier,
                pasteDuration: pasteDuration,
                clipboardRestoreOutcome: restoreOutcome
            )
        }
    }

    private func hasPostEventAccess() -> Bool {
        let granted = CGPreflightPostEventAccess()
        logger.info("Post-event access request result: \(granted, privacy: .public)")
        return granted
    }

    private func copyTranscriptToClipboard(
        _ text: String,
        reason: CueClipboardFallbackReason,
        targetApplication: NSRunningApplication?,
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
            pasteDuration: pasteDuration,
            clipboardRestoreOutcome: .notNeededBecauseTranscriptStayedOnClipboard
        )
    }

    private func frontmostTargetApplication() -> TargetApplicationResolution {
        guard let application = workspace.frontmostApplication else {
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

        return pasteboard.changeCount
    }

    private func postPasteCommand(to processIdentifier: pid_t) throws {
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

    private func restoreSnapshotImmediatelyIfAvailable(_ snapshot: PasteboardSnapshot?) -> Bool {
        guard let snapshot else {
            return false
        }

        return snapshot.restore(to: pasteboard)
    }

    private func restorePasteboardIfNeeded(
        _ snapshot: PasteboardSnapshot?,
        expectedCueChangeCount: Int
    ) async -> ClipboardRestoreOutcome {
        guard let snapshot else {
            return .skippedBecauseSnapshotUnavailable
        }

        try? await Task.sleep(nanoseconds: CueAppConfiguration.clipboardRestoreDelay.nanoseconds)

        guard pasteboard.changeCount == expectedCueChangeCount else {
            return .skippedBecauseClipboardChanged
        }

        guard snapshot.restore(to: pasteboard) else {
            return .failed("Cue could not write the previous clipboard contents back.")
        }

        return .restored
    }
}

private enum TargetApplicationResolution {
    case target(NSRunningApplication)
    case fallback(CueClipboardFallbackReason)
}

@MainActor
private struct PasteboardSnapshot {
    let items: [PasteboardItemSnapshot]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot? {
        guard let pasteboardItems = pasteboard.pasteboardItems else {
            return nil
        }

        let snapshots = pasteboardItems.map(PasteboardItemSnapshot.init).filter(\.hasData)

        if pasteboardItems.isEmpty || !snapshots.isEmpty {
            return PasteboardSnapshot(items: snapshots)
        }

        return nil
    }

    func restore(to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()

        guard !items.isEmpty else {
            return true
        }

        return pasteboard.writeObjects(items.map { $0.makePasteboardItem() })
    }
}

@MainActor
private struct PasteboardItemSnapshot {
    let entries: [(NSPasteboard.PasteboardType, Data)]

    var hasData: Bool {
        !entries.isEmpty
    }

    init(item: NSPasteboardItem) {
        entries = item.types.compactMap { type in
            guard let data = item.data(forType: type) else {
                return nil
            }

            return (type, data)
        }
    }

    func makePasteboardItem() -> NSPasteboardItem {
        let item = NSPasteboardItem()

        for (type, data) in entries {
            item.setData(data, forType: type)
        }

        return item
    }
}

private extension TimeInterval {
    var nanoseconds: UInt64 {
        UInt64(self * 1_000_000_000)
    }
}
