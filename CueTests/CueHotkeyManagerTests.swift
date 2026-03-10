import AppKit
import Foundation
import KeyboardShortcuts
import Testing
@testable import Cue

@MainActor
struct CueHotkeyManagerTests {
    @Test func firstLaunchInitializesDefaultShortcutWhenNoneIsConfigured() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let bindingService = FakeHotkeyBindingService(shortcut: nil)
        let manager = makeManager(defaults: defaults, bindingService: bindingService)

        #expect(bindingService.setShortcutCalls == [defaultPushToTalkShortcut])
        #expect(bindingService.currentShortcut() == defaultPushToTalkShortcut)
        #expect(manager.shortcutSummary == defaultPushToTalkShortcut.description)
        #expect(manager.hasConfiguredShortcut)
    }

    @Test func initializationDoesNotOverrideAnExistingShortcut() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let existingShortcut = KeyboardShortcuts.Shortcut(.r, modifiers: [.command, .option])
        let bindingService = FakeHotkeyBindingService(shortcut: existingShortcut)
        let manager = makeManager(defaults: defaults, bindingService: bindingService)

        #expect(bindingService.setShortcutCalls.isEmpty)
        #expect(manager.shortcutSummary == existingShortcut.description)
        #expect(manager.hasConfiguredShortcut)
    }

    @Test func updateShortcutSummaryTracksConfiguredState() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let bindingService = FakeHotkeyBindingService(shortcut: defaultPushToTalkShortcut)
        let manager = makeManager(defaults: defaults, bindingService: bindingService)
        let updatedShortcut = KeyboardShortcuts.Shortcut(.d, modifiers: [.shift, .option])

        manager.updateShortcutSummary(nil)
        #expect(manager.shortcutSummary == "Not configured")
        #expect(!manager.hasConfiguredShortcut)

        manager.updateShortcutSummary(updatedShortcut)
        #expect(manager.shortcutSummary == updatedShortcut.description)
        #expect(manager.hasConfiguredShortcut)
    }

    @Test func registeredKeyHandlersDrivePushToTalkWorkflow() async throws {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService()
        let soundService = FakeSoundService()
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            soundService: soundService,
            notificationCenter: NotificationCenter()
        )
        let bindingService = FakeHotkeyBindingService(shortcut: defaultPushToTalkShortcut)

        await model.launch()
        let manager = CueHotkeyManager(
            appModel: model,
            defaults: defaults,
            bindingService: bindingService
        )

        _ = manager
        bindingService.triggerKeyDown()
        await yieldUntil { transcriptionService.startRecordingCallCount == 1 }

        #expect(model.sessionState == .recording)
        #expect(soundService.playRecordingStartedCallCount == 1)

        bindingService.triggerKeyUp()
        await yieldUntil { insertionService.insertCallCount == 1 }

        #expect(transcriptionService.stopRecordingCallCount == 1)
        #expect(model.sessionState == .idle)
        #expect(model.transcript == transcriptionService.result.text)
        #expect(soundService.playRecordingStoppedCallCount == 1)
    }

    private func makeManager(
        defaults: UserDefaults,
        bindingService: FakeHotkeyBindingService
    ) -> CueHotkeyManager {
        let model = CueAppModel(
            transcriptionService: FakeTranscriptionService(),
            insertionService: FakeTextInsertionService(),
            permissionService: FakePermissionService(),
            notificationCenter: NotificationCenter()
        )

        return CueHotkeyManager(
            appModel: model,
            defaults: defaults,
            bindingService: bindingService
        )
    }

    private func yieldUntil(
        maxYields: Int = 20,
        condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<maxYields {
            if condition() {
                return
            }

            await Task.yield()
        }
    }
}

private final class FakeHotkeyBindingService: HotkeyBindingService {
    private(set) var shortcut: KeyboardShortcuts.Shortcut?
    private(set) var setShortcutCalls: [KeyboardShortcuts.Shortcut?] = []
    private var keyDownAction: (() -> Void)?
    private var keyUpAction: (() -> Void)?

    init(shortcut: KeyboardShortcuts.Shortcut?) {
        self.shortcut = shortcut
    }

    func currentShortcut() -> KeyboardShortcuts.Shortcut? {
        shortcut
    }

    func setShortcut(_ shortcut: KeyboardShortcuts.Shortcut?) {
        setShortcutCalls.append(shortcut)
        self.shortcut = shortcut
    }

    func registerKeyDown(_ action: @escaping () -> Void) {
        keyDownAction = action
    }

    func registerKeyUp(_ action: @escaping () -> Void) {
        keyUpAction = action
    }

    func triggerKeyDown() {
        keyDownAction?()
    }

    func triggerKeyUp() {
        keyUpAction?()
    }
}
