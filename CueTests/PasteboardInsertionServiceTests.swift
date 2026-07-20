import AppKit
import Foundation
import Testing
@testable import Cue

private let noOpSleep: @Sendable (TimeInterval) async -> Void = { _ in }

@MainActor
struct PasteboardInsertionServiceTests {
    @Test func insertWithoutAccessibilityThrowsError() async throws {
        let rig = PasteboardInsertionTestRig(
            application: CueRunningApplication(
                processIdentifier: 42,
                localizedName: "Notes",
                bundleIdentifier: "com.apple.Notes"
            )
        )
        let service = rig.makeService(hasAccessibilityPermission: false)

        await #expect(throws: CueError.accessibilityPermissionDenied) {
            _ = try await service.insert("hello")
        }

        #expect(rig.pasteboard.writtenStrings.isEmpty)
        #expect(rig.pasteboard.currentPlainText == "before")
    }

    @Test func insertWithoutFrontmostTargetThrowsError() async throws {
        let rig = PasteboardInsertionTestRig(application: nil)
        let service = rig.makeService()

        await #expect(throws: CueError.noFrontmostApplication) {
            _ = try await service.insert("hello")
        }

        #expect(rig.pasteboard.writtenStrings.isEmpty)
    }

    @Test func insertWhenCueIsFrontmostThrowsError() async throws {
        let rig = PasteboardInsertionTestRig(
            application: CueRunningApplication(
                processIdentifier: 7,
                localizedName: "Cue",
                bundleIdentifier: "dev.sonawalla.Cue"
            )
        )
        let service = rig.makeService()

        await #expect(throws: CueError.cannotPasteIntoCue) {
            _ = try await service.insert("hello")
        }

        #expect(rig.pasteboard.writtenStrings.isEmpty)
    }

    @Test func posterFailureThrowsPasteErrorAndRestoresClipboard() async throws {
        let rig = PasteboardInsertionTestRig(
            application: CueRunningApplication(
                processIdentifier: 9,
                localizedName: "Slack",
                bundleIdentifier: "com.tinyspeck.slackmacgap"
            )
        )
        rig.poster.error = NSError(domain: "CueTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "event bridge down"])
        let service = rig.makeService()

        await #expect(throws: CueError.pasteFailed("event bridge down")) {
            _ = try await service.insert("hello")
        }

        #expect(rig.poster.postedProcessIdentifiers == [9])
        #expect(rig.pasteboard.writtenStrings == ["hello"])
        #expect(rig.pasteboard.restoreContentsCallCount == 1)
        #expect(rig.pasteboard.currentPlainText == "before")
    }

    @Test func cuePosterFailurePreservesCueErrorMessageAndRestoresClipboard() async throws {
        let rig = PasteboardInsertionTestRig(
            application: CueRunningApplication(
                processIdentifier: 10,
                localizedName: "Notes",
                bundleIdentifier: "com.apple.Notes"
            )
        )
        rig.poster.error = CueError.pasteFailed("Cue could not synthesize the Command-V keyboard events.")
        let service = rig.makeService()

        await #expect(throws: CueError.pasteFailed("Cue could not synthesize the Command-V keyboard events.")) {
            _ = try await service.insert("hello")
        }

        #expect(rig.poster.postedProcessIdentifiers == [10])
        #expect(rig.pasteboard.writtenStrings == ["hello"])
        #expect(rig.pasteboard.restoreContentsCallCount == 1)
        #expect(rig.pasteboard.currentPlainText == "before")
    }

    @Test func readyTargetPostsPasteCommandAndRestoresClipboard() async throws {
        let rig = PasteboardInsertionTestRig(
            application: CueRunningApplication(
                processIdentifier: 12,
                localizedName: "TextEdit",
                bundleIdentifier: "com.apple.TextEdit"
            )
        )
        let service = rig.makeService()

        _ = try await service.insert("hello")

        #expect(rig.poster.postedProcessIdentifiers == [12])
        #expect(rig.pasteboard.writtenStrings == ["hello"])
        #expect(rig.pasteboard.restoreContentsCallCount == 1)
        #expect(rig.pasteboard.currentPlainText == "before")
    }

    @Test func clipboardChangeDuringGraceWindowSkipsRestore() async throws {
        let rig = PasteboardInsertionTestRig(
            application: CueRunningApplication(
                processIdentifier: 11,
                localizedName: "Mail",
                bundleIdentifier: "com.apple.mail"
            )
        )
        let service = rig.makeService(
            pasteRestoreGracePeriod: 0.2,
            sleepAfterPaste: { _ in
                await MainActor.run {
                    rig.pasteboard.simulateExternalClipboardChange(text: "external clipboard")
                }
            }
        )

        _ = try await service.insert("hello")

        #expect(rig.pasteboard.restoreContentsCallCount == 0)
        #expect(rig.pasteboard.currentPlainText == "external clipboard")
    }

    @Test func snapshotFailureThrowsPasteErrorBeforeOverwrite() async throws {
        let rig = PasteboardInsertionTestRig(
            application: CueRunningApplication(
                processIdentifier: 21,
                localizedName: "Notes",
                bundleIdentifier: "com.apple.Notes"
            )
        )
        rig.pasteboard.snapshotError = CueError.pasteFailed("snapshot unavailable")
        let service = rig.makeService()

        await #expect(throws: CueError.pasteFailed("Cue could not preserve the current clipboard contents.")) {
            _ = try await service.insert("hello")
        }

        #expect(rig.pasteboard.writtenStrings.isEmpty)
        #expect(rig.pasteboard.currentPlainText == "before")
    }

    @Test func restoreFailureKeepsPasteSuccessfulAndLeavesTranscriptOnClipboard() async throws {
        let rig = PasteboardInsertionTestRig(
            application: CueRunningApplication(
                processIdentifier: 13,
                localizedName: "Pages",
                bundleIdentifier: "com.apple.iWork.Pages"
            )
        )
        rig.pasteboard.restoreError = CueError.pasteFailed("restore write failed")
        let service = rig.makeService()

        _ = try await service.insert("hello")

        #expect(rig.pasteboard.restoreContentsCallCount == 1)
        #expect(rig.pasteboard.currentPlainText == "hello")
    }
}

@MainActor
struct SystemPasteboardAccessTests {
    @Test func replaceWritesPlainTextAndPasteboardMetadata() throws {
        let rawPasteboard = RawFakeSystemPasteboard(initialPlainText: "before")
        let access = SystemPasteboardAccess(pasteboard: rawPasteboard)

        let changeCount = try access.replaceContents(
            with: "hello",
            sourceBundleIdentifier: "dev.sonawalla.Cue"
        )

        #expect(changeCount == rawPasteboard.changeCount)
        #expect(rawPasteboard.currentPlainText == "hello")
        #expect(rawPasteboard.data(forType: .init("org.nspasteboard.TransientType")) == Data())
        #expect(rawPasteboard.data(forType: .init("org.nspasteboard.AutoGeneratedType")) == Data())
        #expect(rawPasteboard.string(forType: .init("org.nspasteboard.source")) == "dev.sonawalla.Cue")
    }

    @Test func replaceFailureAfterClearRestoresPreviousClipboard() throws {
        let rawPasteboard = RawFakeSystemPasteboard(initialPlainText: "before")
        let access = SystemPasteboardAccess(pasteboard: rawPasteboard)
        rawPasteboard.failNextWrite = true

        #expect(throws: CueError.pasteFailed("Cue could not write plain text to the system pasteboard.")) {
            _ = try access.replaceContents(
                with: "hello",
                sourceBundleIdentifier: "dev.sonawalla.Cue"
            )
        }

        #expect(rawPasteboard.currentPlainText == "before")
    }

    @Test func restoreFailureAfterClearRestoresCueClipboard() throws {
        let rawPasteboard = RawFakeSystemPasteboard(initialPlainText: "before")
        let access = SystemPasteboardAccess(pasteboard: rawPasteboard)
        _ = try access.replaceContents(
            with: "hello",
            sourceBundleIdentifier: "dev.sonawalla.Cue"
        )
        let originalSnapshot = cueSnapshot(withPlainText: "before")

        rawPasteboard.failNextWrite = true

        #expect(throws: CueError.pasteFailed("Cue could not restore the previous clipboard contents.")) {
            try access.restoreContents(from: originalSnapshot)
        }

        #expect(rawPasteboard.currentPlainText == "hello")
        #expect(rawPasteboard.string(forType: .init("org.nspasteboard.source")) == "dev.sonawalla.Cue")
    }
}

@MainActor
private final class PasteboardInsertionTestRig {
    let pasteboard = FakePasteboardAccess(initialPlainText: "before")
    let poster = FakePasteCommandPoster()

    private let resolver: FakeFrontmostApplicationResolver

    init(application: CueRunningApplication?) {
        resolver = FakeFrontmostApplicationResolver(application: application)
    }

    func makeService(
        hasAccessibilityPermission: Bool = true,
        pasteRestoreGracePeriod: TimeInterval = 0,
        sleepAfterPaste: @escaping @Sendable (TimeInterval) async -> Void = noOpSleep
    ) -> PasteboardInsertionService {
        PasteboardInsertionService(
            applicationResolver: resolver,
            pasteboard: pasteboard,
            pasteCommandPoster: poster,
            hasAccessibilityPermission: { hasAccessibilityPermission },
            mainBundleIdentifier: CueAppConfiguration.bundleIdentifier,
            pasteRestoreGracePeriod: pasteRestoreGracePeriod,
            sleepAfterPaste: sleepAfterPaste
        )
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
    var restoreContentsCallCount = 0
    var snapshotError: Error?
    var restoreError: Error?
    var writtenStrings: [String] = []

    private var currentSnapshot: CuePasteboardSnapshot
    private(set) var changeCount = 0

    init(initialPlainText: String) {
        currentSnapshot = Self.snapshot(withPlainText: initialPlainText)
    }

    var currentPlainText: String? {
        Self.plainText(in: currentSnapshot)
    }

    func snapshotContents() throws -> CuePasteboardSnapshot {
        if let snapshotError {
            throw snapshotError
        }

        return currentSnapshot
    }

    func replaceContents(with text: String, sourceBundleIdentifier: String?) throws -> Int {
        writtenStrings.append(text)
        currentSnapshot = Self.snapshot(withPlainText: text)
        changeCount += 1
        return changeCount
    }

    func restoreContents(from snapshot: CuePasteboardSnapshot) throws {
        restoreContentsCallCount += 1

        if let restoreError {
            throw restoreError
        }

        currentSnapshot = snapshot
        changeCount += 1
    }

    func simulateExternalClipboardChange(text: String) {
        currentSnapshot = Self.snapshot(withPlainText: text)
        changeCount += 1
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

    func data(forType type: NSPasteboard.PasteboardType) -> Data? {
        for item in currentSnapshot.items {
            for representation in item.representations where representation.type == type {
                return representation.data
            }
        }

        return nil
    }

    func string(forType type: NSPasteboard.PasteboardType) -> String? {
        data(forType: type).flatMap { String(data: $0, encoding: .utf8) }
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

private func plainText(in snapshot: CuePasteboardSnapshot) -> String? {
    for item in snapshot.items {
        for representation in item.representations where representation.type == .string {
            return String(data: representation.data, encoding: .utf8)
        }
    }

    return nil
}
