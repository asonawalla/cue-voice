import AppKit
import Foundation
import Testing
@testable import Cue

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
        let pasteboard = FakePasteboardWriter()
        let poster = FakePasteCommandPoster()
        let service = PasteboardInsertionService(
            applicationResolver: resolver,
            pasteboard: pasteboard,
            pasteCommandPoster: poster,
            hasAccessibilityPermission: { false },
            mainBundleIdentifier: "dev.sonawalla.Cue"
        )

        await #expect(throws: CueError.accessibilityPermissionDenied) {
            _ = try await service.insert("hello")
        }
    }

    @Test func insertWithoutFrontmostTargetThrowsError() async throws {
        let pasteboard = FakePasteboardWriter()
        let service = PasteboardInsertionService(
            applicationResolver: FakeFrontmostApplicationResolver(application: nil),
            pasteboard: pasteboard,
            pasteCommandPoster: FakePasteCommandPoster(),
            hasAccessibilityPermission: { true },
            mainBundleIdentifier: "dev.sonawalla.Cue"
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
        let pasteboard = FakePasteboardWriter()
        let service = PasteboardInsertionService(
            applicationResolver: resolver,
            pasteboard: pasteboard,
            pasteCommandPoster: FakePasteCommandPoster(),
            hasAccessibilityPermission: { true },
            mainBundleIdentifier: "dev.sonawalla.Cue"
        )

        await #expect(throws: CueError.cannotPasteIntoCue) {
            _ = try await service.insert("hello")
        }

        #expect(pasteboard.writtenStrings.isEmpty)
    }

    @Test func posterFailureThrowsPasteError() async throws {
        let resolver = FakeFrontmostApplicationResolver(
            application: CueRunningApplication(
                processIdentifier: 9,
                localizedName: "Slack",
                bundleIdentifier: "com.tinyspeck.slackmacgap"
            )
        )
        let pasteboard = FakePasteboardWriter()
        let poster = FakePasteCommandPoster()
        poster.error = NSError(domain: "CueTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "event bridge down"])
        let service = PasteboardInsertionService(
            applicationResolver: resolver,
            pasteboard: pasteboard,
            pasteCommandPoster: poster,
            hasAccessibilityPermission: { true },
            mainBundleIdentifier: "dev.sonawalla.Cue"
        )

        await #expect(throws: CueError.pasteFailed("event bridge down")) {
            _ = try await service.insert("hello")
        }

        #expect(poster.postedProcessIdentifiers == [9])
        #expect(pasteboard.writtenStrings == ["hello"])
    }

    @Test func readyTargetPostsPasteCommand() async throws {
        let resolver = FakeFrontmostApplicationResolver(
            application: CueRunningApplication(
                processIdentifier: 12,
                localizedName: "TextEdit",
                bundleIdentifier: "com.apple.TextEdit"
            )
        )
        let pasteboard = FakePasteboardWriter()
        let poster = FakePasteCommandPoster()
        let service = PasteboardInsertionService(
            applicationResolver: resolver,
            pasteboard: pasteboard,
            pasteCommandPoster: poster,
            hasAccessibilityPermission: { true },
            mainBundleIdentifier: "dev.sonawalla.Cue"
        )

        let result = try await service.insert("hello")

        #expect(result.delivery == .pasteCommandSent)
        #expect(result.targetAppName == "TextEdit")
        #expect(poster.postedProcessIdentifiers == [12])
        #expect(pasteboard.writtenStrings == ["hello"])
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
private final class FakePasteboardWriter: CuePasteboardWriting {
    var writtenStrings: [String] = []
    var shouldSucceed = true

    func clearContents() {}

    func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool {
        _ = type

        guard shouldSucceed else {
            return false
        }

        writtenStrings.append(string)
        return true
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
