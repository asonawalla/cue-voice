import AppKit
import Foundation
import Testing
@testable import Cue

private let noOpSleep: @Sendable (TimeInterval) async -> Void = { _ in }

@MainActor
struct PasteboardInsertionServiceTests {
    @Test func insertWithoutAccessibilityThrowsError() async throws {
        let resolver = FakeFrontmostApplicationResolver(
            application: CueRunningApplication(
                processIdentifier: 42,
                localizedName: "Notes",
                bundleIdentifier: "com.apple.Notes"
            )
        )
        let pasteboard = FakePasteboardAccess(initialPlainText: "before")
        let poster = FakePasteCommandPoster()
        let service = PasteboardInsertionService(
            applicationResolver: resolver,
            pasteboard: pasteboard,
            pasteCommandPoster: poster,
            hasAccessibilityPermission: { false },
            mainBundleIdentifier: "dev.sonawalla.Cue",
            pasteRestoreGracePeriod: 0,
            sleepAfterPaste: noOpSleep
        )

        await #expect(throws: CueError.accessibilityPermissionDenied) {
            _ = try await service.insert("hello")
        }

        #expect(pasteboard.writtenStrings.isEmpty)
        #expect(pasteboard.currentPlainText == "before")
    }

    @Test func insertWithoutFrontmostTargetThrowsError() async throws {
        let pasteboard = FakePasteboardAccess(initialPlainText: "before")
        let service = PasteboardInsertionService(
            applicationResolver: FakeFrontmostApplicationResolver(application: nil),
            pasteboard: pasteboard,
            pasteCommandPoster: FakePasteCommandPoster(),
            hasAccessibilityPermission: { true },
            mainBundleIdentifier: "dev.sonawalla.Cue",
            pasteRestoreGracePeriod: 0,
            sleepAfterPaste: noOpSleep
        )

        await #expect(throws: CueError.noFrontmostApplication) {
            _ = try await service.insert("hello")
        }

        #expect(pasteboard.writtenStrings.isEmpty)
    }

    @Test func insertWhenCueIsFrontmostThrowsError() async throws {
        let resolver = FakeFrontmostApplicationResolver(
            application: CueRunningApplication(
                processIdentifier: 7,
                localizedName: "Cue",
                bundleIdentifier: "dev.sonawalla.Cue"
            )
        )
        let pasteboard = FakePasteboardAccess(initialPlainText: "before")
        let service = PasteboardInsertionService(
            applicationResolver: resolver,
            pasteboard: pasteboard,
            pasteCommandPoster: FakePasteCommandPoster(),
            hasAccessibilityPermission: { true },
            mainBundleIdentifier: "dev.sonawalla.Cue",
            pasteRestoreGracePeriod: 0,
            sleepAfterPaste: noOpSleep
        )

        await #expect(throws: CueError.cannotPasteIntoCue) {
            _ = try await service.insert("hello")
        }

        #expect(pasteboard.writtenStrings.isEmpty)
    }

    @Test func posterFailureThrowsPasteErrorAndRestoresClipboard() async throws {
        let resolver = FakeFrontmostApplicationResolver(
            application: CueRunningApplication(
                processIdentifier: 9,
                localizedName: "Slack",
                bundleIdentifier: "com.tinyspeck.slackmacgap"
            )
        )
        let pasteboard = FakePasteboardAccess(initialPlainText: "before")
        let poster = FakePasteCommandPoster()
        poster.error = NSError(domain: "CueTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "event bridge down"])
        let service = PasteboardInsertionService(
            applicationResolver: resolver,
            pasteboard: pasteboard,
            pasteCommandPoster: poster,
            hasAccessibilityPermission: { true },
            mainBundleIdentifier: "dev.sonawalla.Cue",
            pasteRestoreGracePeriod: 0,
            sleepAfterPaste: noOpSleep
        )

        await #expect(throws: CueError.pasteFailed("event bridge down")) {
            _ = try await service.insert("hello")
        }

        #expect(poster.postedProcessIdentifiers == [9])
        #expect(pasteboard.writtenStrings == ["hello"])
        #expect(pasteboard.restoreContentsCallCount == 1)
        #expect(pasteboard.currentPlainText == "before")
    }

    @Test func readyTargetPostsPasteCommandAndRestoresClipboard() async throws {
        let resolver = FakeFrontmostApplicationResolver(
            application: CueRunningApplication(
                processIdentifier: 12,
                localizedName: "TextEdit",
                bundleIdentifier: "com.apple.TextEdit"
            )
        )
        let pasteboard = FakePasteboardAccess(initialPlainText: "before")
        let poster = FakePasteCommandPoster()
        let service = PasteboardInsertionService(
            applicationResolver: resolver,
            pasteboard: pasteboard,
            pasteCommandPoster: poster,
            hasAccessibilityPermission: { true },
            mainBundleIdentifier: "dev.sonawalla.Cue",
            pasteRestoreGracePeriod: 0,
            sleepAfterPaste: noOpSleep
        )

        let result = try await service.insert("hello")

        #expect(result.delivery == .pasteCommandSent)
        #expect(result.targetAppName == "TextEdit")
        #expect(result.clipboardRestoreState == .restored)
        #expect(poster.postedProcessIdentifiers == [12])
        #expect(pasteboard.writtenStrings == ["hello"])
        #expect(pasteboard.restoreContentsCallCount == 1)
        #expect(pasteboard.currentPlainText == "before")
    }

    @Test func clipboardChangeDuringGraceWindowSkipsRestore() async throws {
        let resolver = FakeFrontmostApplicationResolver(
            application: CueRunningApplication(
                processIdentifier: 11,
                localizedName: "Mail",
                bundleIdentifier: "com.apple.mail"
            )
        )
        let pasteboard = FakePasteboardAccess(initialPlainText: "before")
        let service = PasteboardInsertionService(
            applicationResolver: resolver,
            pasteboard: pasteboard,
            pasteCommandPoster: FakePasteCommandPoster(),
            hasAccessibilityPermission: { true },
            mainBundleIdentifier: "dev.sonawalla.Cue",
            pasteRestoreGracePeriod: 0.2,
            sleepAfterPaste: { _ in
                await MainActor.run {
                    pasteboard.simulateExternalClipboardChange(text: "external clipboard")
                }
            }
        )

        let result = try await service.insert("hello")

        #expect(result.clipboardRestoreState == .skippedClipboardChanged)
        #expect(pasteboard.restoreContentsCallCount == 0)
        #expect(pasteboard.currentPlainText == "external clipboard")
    }

    @Test func snapshotFailureThrowsPasteErrorBeforeOverwrite() async throws {
        let resolver = FakeFrontmostApplicationResolver(
            application: CueRunningApplication(
                processIdentifier: 21,
                localizedName: "Notes",
                bundleIdentifier: "com.apple.Notes"
            )
        )
        let pasteboard = FakePasteboardAccess(initialPlainText: "before")
        pasteboard.snapshotError = CueError.pasteFailed("snapshot unavailable")
        let service = PasteboardInsertionService(
            applicationResolver: resolver,
            pasteboard: pasteboard,
            pasteCommandPoster: FakePasteCommandPoster(),
            hasAccessibilityPermission: { true },
            mainBundleIdentifier: "dev.sonawalla.Cue",
            pasteRestoreGracePeriod: 0,
            sleepAfterPaste: noOpSleep
        )

        await #expect(throws: CueError.pasteFailed("Cue could not preserve the current clipboard contents.")) {
            _ = try await service.insert("hello")
        }

        #expect(pasteboard.writtenStrings.isEmpty)
        #expect(pasteboard.currentPlainText == "before")
    }

    @Test func restoreFailureKeepsPasteSuccessfulAndReportsFailedRestore() async throws {
        let resolver = FakeFrontmostApplicationResolver(
            application: CueRunningApplication(
                processIdentifier: 13,
                localizedName: "Pages",
                bundleIdentifier: "com.apple.iWork.Pages"
            )
        )
        let pasteboard = FakePasteboardAccess(initialPlainText: "before")
        pasteboard.restoreError = CueError.pasteFailed("restore write failed")
        let service = PasteboardInsertionService(
            applicationResolver: resolver,
            pasteboard: pasteboard,
            pasteCommandPoster: FakePasteCommandPoster(),
            hasAccessibilityPermission: { true },
            mainBundleIdentifier: "dev.sonawalla.Cue",
            pasteRestoreGracePeriod: 0,
            sleepAfterPaste: noOpSleep
        )

        let result = try await service.insert("hello")

        #expect(result.clipboardRestoreState == .failed)
        #expect(pasteboard.restoreContentsCallCount == 1)
        #expect(pasteboard.currentPlainText == "hello")
    }
}

@MainActor
struct SystemPasteboardAccessTests {
    @Test func replaceFailureAfterClearRestoresPreviousClipboard() throws {
        let rawPasteboard = RawFakeSystemPasteboard(initialPlainText: "before")
        let access = SystemPasteboardAccess(pasteboard: rawPasteboard)
        rawPasteboard.failNextWrite = true

        #expect(throws: CueError.pasteFailed("Cue could not write plain text to the system pasteboard.")) {
            _ = try access.replaceContents(
                with: "hello",
                ownershipToken: "token-1",
                sourceBundleIdentifier: "dev.sonawalla.Cue"
            )
        }

        #expect(rawPasteboard.currentPlainText == "before")
        #expect(rawPasteboard.currentOwnershipToken == nil)
    }

    @Test func restoreFailureAfterClearRestoresCueClipboard() throws {
        let rawPasteboard = RawFakeSystemPasteboard(initialPlainText: "before")
        let access = SystemPasteboardAccess(pasteboard: rawPasteboard)
        _ = try access.replaceContents(
            with: "hello",
            ownershipToken: "token-2",
            sourceBundleIdentifier: "dev.sonawalla.Cue"
        )
        let originalSnapshot = cueSnapshot(withPlainText: "before")

        rawPasteboard.failNextWrite = true

        #expect(throws: CueError.pasteFailed("Cue could not restore the previous clipboard contents.")) {
            _ = try access.restoreContents(from: originalSnapshot)
        }

        #expect(rawPasteboard.currentPlainText == "hello")
        #expect(rawPasteboard.currentOwnershipToken == "token-2")
    }
}

@MainActor
private final class FakeFrontmostApplicationResolver: FrontmostApplicationResolving {
    var application: CueRunningApplication?

    init(application: CueRunningApplication?) {
        self.application = application
    }

    func frontmostApplication() -> CueRunningApplication? {
        application
    }
}

@MainActor
private final class FakePasteboardAccess: CuePasteboardAccessing {
    private static let ownershipTokenType = NSPasteboard.PasteboardType("dev.sonawalla.Cue.pasteToken")
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static let autoGeneratedType = NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")
    private static let sourceType = NSPasteboard.PasteboardType("org.nspasteboard.source")

    var snapshotContentsCallCount = 0
    var replaceContentsCallCount = 0
    var restoreContentsCallCount = 0
    var snapshotError: Error?
    var replaceError: Error?
    var restoreError: Error?
    var writtenStrings: [String] = []

    private(set) var currentSnapshot: CuePasteboardSnapshot
    private(set) var currentChangeCount = 0
    private(set) var currentOwnershipToken: String?

    init(initialPlainText: String) {
        currentSnapshot = Self.snapshot(withPlainText: initialPlainText)
        currentOwnershipToken = Self.ownershipToken(in: currentSnapshot)
    }

    var currentPlainText: String? {
        Self.plainText(in: currentSnapshot)
    }

    func snapshotContents() throws -> CuePasteboardSnapshot {
        snapshotContentsCallCount += 1

        if let snapshotError {
            throw snapshotError
        }

        return currentSnapshot
    }

    func replaceContents(with text: String, ownershipToken: String, sourceBundleIdentifier: String?) throws -> Int {
        replaceContentsCallCount += 1

        if let replaceError {
            throw replaceError
        }

        writtenStrings.append(text)
        currentSnapshot = Self.cueSnapshot(
            withPlainText: text,
            ownershipToken: ownershipToken,
            sourceBundleIdentifier: sourceBundleIdentifier
        )
        currentOwnershipToken = ownershipToken
        currentChangeCount += 1
        return currentChangeCount
    }

    func restoreContents(from snapshot: CuePasteboardSnapshot) throws -> Int {
        restoreContentsCallCount += 1

        if let restoreError {
            throw restoreError
        }

        currentSnapshot = snapshot
        currentOwnershipToken = Self.ownershipToken(in: snapshot)
        currentChangeCount += 1
        return currentChangeCount
    }

    func currentOwnership() -> CuePasteboardOwnership {
        CuePasteboardOwnership(changeCount: currentChangeCount, token: currentOwnershipToken)
    }

    func simulateExternalClipboardChange(text: String) {
        currentSnapshot = Self.snapshot(withPlainText: text)
        currentOwnershipToken = nil
        currentChangeCount += 1
    }

    private static func snapshot(withPlainText text: String) -> CuePasteboardSnapshot {
        CuePasteboardSnapshot(
            items: [
                CuePasteboardItemSnapshot(
                    representations: [
                        CuePasteboardRepresentation(type: .string, data: Data(text.utf8))
                    ]
                )
            ]
        )
    }

    private static func cueSnapshot(
        withPlainText text: String,
        ownershipToken: String,
        sourceBundleIdentifier: String?
    ) -> CuePasteboardSnapshot {
        var representations = [
            CuePasteboardRepresentation(type: .string, data: Data(text.utf8)),
            CuePasteboardRepresentation(type: transientType, data: Data()),
            CuePasteboardRepresentation(type: autoGeneratedType, data: Data()),
            CuePasteboardRepresentation(type: ownershipTokenType, data: Data(ownershipToken.utf8))
        ]

        if let sourceBundleIdentifier {
            representations.append(
                CuePasteboardRepresentation(type: sourceType, data: Data(sourceBundleIdentifier.utf8))
            )
        }

        return CuePasteboardSnapshot(items: [CuePasteboardItemSnapshot(representations: representations)])
    }

    private static func ownershipToken(in snapshot: CuePasteboardSnapshot) -> String? {
        for item in snapshot.items {
            for representation in item.representations where representation.type == ownershipTokenType {
                return String(data: representation.data, encoding: .utf8)
            }
        }

        return nil
    }

    private static func plainText(in snapshot: CuePasteboardSnapshot) -> String? {
        for item in snapshot.items {
            for representation in item.representations where representation.type == .string {
                return String(data: representation.data, encoding: .utf8)
            }
        }

        return nil
    }
}

@MainActor
private final class FakePasteCommandPoster: PasteCommandPosting {
    var postedProcessIdentifiers: [pid_t] = []
    var error: Error?

    func postPasteCommand(to processIdentifier: pid_t) throws {
        postedProcessIdentifiers.append(processIdentifier)

        if let error {
            throw error
        }
    }
}

@MainActor
private final class RawFakeSystemPasteboard: RawSystemPasteboardAccessing {
    var changeCount: Int = 0
    var failNextWrite = false

    private(set) var currentSnapshot: CuePasteboardSnapshot

    init(initialPlainText: String) {
        currentSnapshot = cueSnapshot(withPlainText: initialPlainText)
    }

    var pasteboardItems: [NSPasteboardItem]? {
        currentSnapshot.items.map { snapshotItem in
            let item = NSPasteboardItem()

            for representation in snapshotItem.representations {
                _ = item.setData(representation.data, forType: representation.type)
            }

            return item
        }
    }

    var currentPlainText: String? {
        plainText(in: currentSnapshot)
    }

    var currentOwnershipToken: String? {
        ownershipToken(in: currentSnapshot)
    }

    @discardableResult
    func clearContents() -> Int {
        currentSnapshot = CuePasteboardSnapshot(items: [])
        changeCount += 1
        return changeCount
    }

    func writeItems(_ items: [NSPasteboardItem]) -> Bool {
        if failNextWrite {
            failNextWrite = false
            return false
        }

        currentSnapshot = snapshot(from: items)
        changeCount += 1
        return true
    }

    func string(forType type: NSPasteboard.PasteboardType) -> String? {
        for item in currentSnapshot.items {
            for representation in item.representations where representation.type == type {
                return String(data: representation.data, encoding: .utf8)
            }
        }

        return nil
    }
}

private func cueSnapshot(withPlainText text: String) -> CuePasteboardSnapshot {
    CuePasteboardSnapshot(
        items: [
            CuePasteboardItemSnapshot(
                representations: [
                    CuePasteboardRepresentation(type: .string, data: Data(text.utf8))
                ]
            )
        ]
    )
}

private func snapshot(from items: [NSPasteboardItem]) -> CuePasteboardSnapshot {
    CuePasteboardSnapshot(
        items: items.map { item in
            CuePasteboardItemSnapshot(
                representations: item.types.compactMap { type in
                    item.data(forType: type).map { CuePasteboardRepresentation(type: type, data: $0) }
                }
            )
        }
    )
}

private func ownershipToken(in snapshot: CuePasteboardSnapshot) -> String? {
    let tokenType = NSPasteboard.PasteboardType("dev.sonawalla.Cue.pasteToken")

    for item in snapshot.items {
        for representation in item.representations where representation.type == tokenType {
            return String(data: representation.data, encoding: .utf8)
        }
    }

    return nil
}

private func plainText(in snapshot: CuePasteboardSnapshot) -> String? {
    for item in snapshot.items {
        for representation in item.representations where representation.type == .string {
            return String(data: representation.data, encoding: .utf8)
        }
    }

    return nil
}
