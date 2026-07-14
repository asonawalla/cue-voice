import AppKit
import CoreGraphics
import Foundation
import os

private func cueDefaultPasteboardRestoreSleep(_ duration: TimeInterval) async {
    guard duration > 0 else {
        return
    }

    let nanoseconds = UInt64(duration * 1_000_000_000)
    try? await Task.sleep(nanoseconds: nanoseconds)
}

private enum ClipboardRestoreState {
    case restored
    case skippedClipboardChanged
    case failed
}

@MainActor
protocol TextInsertionService: AnyObject {
    func insert(_ text: String) async throws -> CueInsertionResult
}

struct CueRunningApplication {
    let processIdentifier: pid_t
    let localizedName: String?
    let bundleIdentifier: String?
}

protocol FrontmostApplicationResolving {
    func frontmostApplication() -> CueRunningApplication?
}

struct CuePasteboardRepresentation {
    let type: NSPasteboard.PasteboardType
    let data: Data
}

struct CuePasteboardItemSnapshot {
    let representations: [CuePasteboardRepresentation]
}

struct CuePasteboardSnapshot {
    let items: [CuePasteboardItemSnapshot]
}

struct CuePasteboardOwnership {
    let changeCount: Int
    let token: String?
}

protocol CuePasteboardAccessing: AnyObject {
    func snapshotContents() throws -> CuePasteboardSnapshot
    func replaceContents(with text: String, ownershipToken: String, sourceBundleIdentifier: String?) throws -> Int
    func restoreContents(from snapshot: CuePasteboardSnapshot) throws -> Int
    func currentOwnership() -> CuePasteboardOwnership
}

protocol RawSystemPasteboardAccessing: AnyObject {
    var changeCount: Int { get }
    var pasteboardItems: [NSPasteboardItem]? { get }
    @discardableResult
    func clearContents() -> Int
    func writeItems(_ items: [NSPasteboardItem]) -> Bool
    func string(forType type: NSPasteboard.PasteboardType) -> String?
}

protocol PasteCommandPosting {
    func postPasteCommand(to processIdentifier: pid_t) throws
}

@MainActor
final class PasteboardInsertionService: TextInsertionService {
    private let applicationResolver: FrontmostApplicationResolving
    private let pasteboard: CuePasteboardAccessing
    private let pasteCommandPoster: PasteCommandPosting
    private let hasAccessibilityPermission: () -> Bool
    private let mainBundleIdentifier: String?
    private let pasteRestoreGracePeriod: TimeInterval
    private let sleepAfterPaste: @Sendable (TimeInterval) async -> Void
    private let logger = Logger(subsystem: "dev.sonawalla.Cue", category: "Insertion")

    init(
        applicationResolver: FrontmostApplicationResolving? = nil,
        pasteboard: CuePasteboardAccessing? = nil,
        pasteCommandPoster: PasteCommandPosting? = nil,
        hasAccessibilityPermission: @escaping () -> Bool = { CGPreflightPostEventAccess() },
        mainBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        pasteRestoreGracePeriod: TimeInterval = 0.2,
        sleepAfterPaste: @escaping @Sendable (TimeInterval) async -> Void = cueDefaultPasteboardRestoreSleep
    ) {
        self.applicationResolver = applicationResolver ?? WorkspaceFrontmostApplicationResolver()
        self.pasteboard = pasteboard ?? SystemPasteboardAccess()
        self.pasteCommandPoster = pasteCommandPoster ?? CGEventPasteCommandPoster()
        self.hasAccessibilityPermission = hasAccessibilityPermission
        self.mainBundleIdentifier = mainBundleIdentifier
        self.pasteRestoreGracePeriod = pasteRestoreGracePeriod
        self.sleepAfterPaste = sleepAfterPaste
    }

    func insert(_ text: String) async throws -> CueInsertionResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CueError.emptyTranscript
        }

        let targetApplication = try frontmostTargetApplication()

        guard hasAccessibilityPermission() else {
            throw CueError.accessibilityPermissionDenied
        }

        let insertionStartedAt = Date()
        let clipboardSnapshot: CuePasteboardSnapshot

        do {
            clipboardSnapshot = try pasteboard.snapshotContents()
        } catch {
            logger.error("Failed to snapshot the system pasteboard: \(error.localizedDescription, privacy: .public)")
            throw CueError.pasteFailed("Cue could not preserve the current clipboard contents.")
        }

        let ownershipToken = UUID().uuidString
        let cueChangeCount: Int

        do {
            cueChangeCount = try pasteboard.replaceContents(
                with: text,
                ownershipToken: ownershipToken,
                sourceBundleIdentifier: mainBundleIdentifier
            )
        } catch {
            logger.error("Failed to write transcript to the pasteboard: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        let targetAppName = targetApplication.localizedName ?? targetApplication.bundleIdentifier ?? "Unknown App"

        do {
            try pasteCommandPoster.postPasteCommand(to: targetApplication.processIdentifier)
        } catch {
            let message = CueCopy.errorMessage(for: error)
            logger.error(
                "Failed to send paste command to \(targetApplication.localizedName ?? targetApplication.bundleIdentifier ?? "unknown app", privacy: .public): \(message, privacy: .public)"
            )

            let restoreState = restoreClipboardIfOwned(
                from: clipboardSnapshot,
                expectedOwnershipToken: ownershipToken,
                expectedChangeCount: cueChangeCount
            )
            logClipboardRestoreState(
                restoreState,
                targetAppName: targetAppName,
                context: "paste command failure"
            )

            if let cueError = error as? CueError {
                throw cueError
            }

            throw CueError.pasteFailed(message)
        }

        let pasteCommandPostedAt = Date()
        await sleepAfterPaste(pasteRestoreGracePeriod)

        let restoreState = restoreClipboardIfOwned(
            from: clipboardSnapshot,
            expectedOwnershipToken: ownershipToken,
            expectedChangeCount: cueChangeCount
        )
        let pasteDuration = Date().timeIntervalSince(insertionStartedAt)

        logClipboardRestoreState(restoreState, targetAppName: targetAppName, context: "successful paste")

        return CueInsertionResult(
            pasteDuration: pasteDuration,
            pasteCommandPostedAt: pasteCommandPostedAt
        )
    }

    private func frontmostTargetApplication() throws -> CueRunningApplication {
        guard let application = applicationResolver.frontmostApplication() else {
            throw CueError.noFrontmostApplication
        }

        if let mainBundleIdentifier, application.bundleIdentifier == mainBundleIdentifier {
            throw CueError.cannotPasteIntoCue
        }

        guard application.localizedName != nil || application.bundleIdentifier != nil else {
            throw CueError.noFrontmostApplication
        }

        return application
    }

    private func restoreClipboardIfOwned(
        from snapshot: CuePasteboardSnapshot,
        expectedOwnershipToken: String,
        expectedChangeCount: Int
    ) -> ClipboardRestoreState {
        let ownership = pasteboard.currentOwnership()

        guard ownership.changeCount == expectedChangeCount, ownership.token == expectedOwnershipToken else {
            return .skippedClipboardChanged
        }

        do {
            _ = try pasteboard.restoreContents(from: snapshot)
            return .restored
        } catch {
            logger.error("Failed to restore the previous clipboard contents: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    private func logClipboardRestoreState(
        _ restoreState: ClipboardRestoreState,
        targetAppName: String,
        context: String
    ) {
        switch restoreState {
        case .restored:
            logger.info(
                "Sent paste command to \(targetAppName, privacy: .public); restored previous clipboard after \(context, privacy: .public)"
            )
        case .skippedClipboardChanged:
            logger.info(
                "Sent paste command to \(targetAppName, privacy: .public); skipped clipboard restore after \(context, privacy: .public) because clipboard contents changed"
            )
        case .failed:
            logger.error(
                "Sent paste command to \(targetAppName, privacy: .public); failed to restore previous clipboard after \(context, privacy: .public)"
            )
        }
    }
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

extension NSPasteboard: RawSystemPasteboardAccessing {
    func writeItems(_ items: [NSPasteboardItem]) -> Bool {
        writeObjects(items)
    }
}

final class SystemPasteboardAccess: CuePasteboardAccessing {
    private static let ownershipTokenType = NSPasteboard.PasteboardType("dev.sonawalla.Cue.pasteToken")
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static let autoGeneratedType = NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")
    private static let sourceType = NSPasteboard.PasteboardType("org.nspasteboard.source")

    private let pasteboard: RawSystemPasteboardAccessing

    init(pasteboard: RawSystemPasteboardAccessing = NSPasteboard.general) {
        self.pasteboard = pasteboard
    }

    func snapshotContents() throws -> CuePasteboardSnapshot {
        guard let pasteboardItems = pasteboard.pasteboardItems else {
            throw CueError.pasteFailed("Cue could not preserve the current clipboard contents.")
        }

        var snapshotItems: [CuePasteboardItemSnapshot] = []

        for pasteboardItem in pasteboardItems {
            var representations: [CuePasteboardRepresentation] = []

            for type in pasteboardItem.types {
                guard let data = pasteboardItem.data(forType: type) else {
                    throw CueError.pasteFailed("Cue could not preserve the current clipboard contents.")
                }

                representations.append(CuePasteboardRepresentation(type: type, data: data))
            }

            snapshotItems.append(CuePasteboardItemSnapshot(representations: representations))
        }

        return CuePasteboardSnapshot(items: snapshotItems)
    }

    func replaceContents(with text: String, ownershipToken: String, sourceBundleIdentifier: String?) throws -> Int {
        let rollbackSnapshot = try? snapshotContents()
        let pasteboardItem = NSPasteboardItem()

        guard pasteboardItem.setString(text, forType: .string) else {
            throw CueError.pasteFailed("Cue could not write plain text to the system pasteboard.")
        }

        guard pasteboardItem.setData(Data(), forType: Self.transientType) else {
            throw CueError.pasteFailed("Cue could not mark the transcript as transient on the system pasteboard.")
        }

        guard pasteboardItem.setData(Data(), forType: Self.autoGeneratedType) else {
            throw CueError.pasteFailed("Cue could not mark the transcript as auto-generated on the system pasteboard.")
        }

        guard pasteboardItem.setString(ownershipToken, forType: Self.ownershipTokenType) else {
            throw CueError.pasteFailed("Cue could not track pasteboard ownership for this paste.")
        }

        if let sourceBundleIdentifier,
           !pasteboardItem.setString(sourceBundleIdentifier, forType: Self.sourceType) {
            throw CueError.pasteFailed("Cue could not mark the pasteboard source for this paste.")
        }

        return try writePreparedItems(
            [pasteboardItem],
            rollbackSnapshot: rollbackSnapshot,
            failureMessage: "Cue could not write plain text to the system pasteboard."
        )
    }

    func restoreContents(from snapshot: CuePasteboardSnapshot) throws -> Int {
        let rollbackSnapshot = try? snapshotContents()
        let itemsToRestore = try buildPasteboardItems(from: snapshot)

        return try writePreparedItems(
            itemsToRestore,
            rollbackSnapshot: rollbackSnapshot,
            failureMessage: "Cue could not restore the previous clipboard contents."
        )
    }

    private func buildPasteboardItems(from snapshot: CuePasteboardSnapshot) throws -> [NSPasteboardItem] {
        guard !snapshot.items.isEmpty else {
            return []
        }

        var itemsToRestore: [NSPasteboardItem] = []

        for snapshotItem in snapshot.items {
            let pasteboardItem = NSPasteboardItem()

            for representation in snapshotItem.representations {
                guard pasteboardItem.setData(representation.data, forType: representation.type) else {
                    throw CueError.pasteFailed("Cue could not restore the previous clipboard contents.")
                }
            }

            itemsToRestore.append(pasteboardItem)
        }

        return itemsToRestore
    }

    private func writePreparedItems(
        _ items: [NSPasteboardItem],
        rollbackSnapshot: CuePasteboardSnapshot?,
        failureMessage: String
    ) throws -> Int {
        pasteboard.clearContents()

        guard !items.isEmpty else {
            return pasteboard.changeCount
        }

        guard pasteboard.writeItems(items) else {
            rollbackToSnapshotIfPossible(rollbackSnapshot)
            throw CueError.pasteFailed(failureMessage)
        }

        return pasteboard.changeCount
    }

    private func rollbackToSnapshotIfPossible(_ snapshot: CuePasteboardSnapshot?) {
        guard let snapshot else {
            return
        }

        if snapshot.items.isEmpty {
            return
        }

        guard let rollbackItems = try? buildPasteboardItems(from: snapshot) else {
            return
        }

        pasteboard.clearContents()
        _ = pasteboard.writeItems(rollbackItems)
    }

    func currentOwnership() -> CuePasteboardOwnership {
        let initialChangeCount = pasteboard.changeCount
        let token = pasteboard.string(forType: Self.ownershipTokenType)
        let finalChangeCount = pasteboard.changeCount

        if initialChangeCount != finalChangeCount {
            return CuePasteboardOwnership(changeCount: finalChangeCount, token: nil)
        }

        return CuePasteboardOwnership(changeCount: finalChangeCount, token: token)
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
