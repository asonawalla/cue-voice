import AppKit
import Foundation
import KeyboardShortcuts
import Testing
@testable import Cue

@MainActor
struct CueHotkeyManagerTests {
    @Test func managerDisplaysTheShortcutReportedByTheBindingService() {
        let rig = CueAppModelTestRig()
        let existingShortcut = KeyboardShortcuts.Shortcut(.r, modifiers: [.command, .option])
        let bindingService = FakeHotkeyBindingService(shortcut: existingShortcut)
        let manager = CueHotkeyManager(appModel: rig.model, bindingService: bindingService)

        #expect(manager.shortcutSummary == existingShortcut.description)
        #expect(manager.hasConfiguredShortcut)
    }

    @Test func managerPreservesAnExplicitlyClearedShortcut() {
        let rig = CueAppModelTestRig()
        let manager = CueHotkeyManager(
            appModel: rig.model,
            bindingService: FakeHotkeyBindingService(shortcut: nil)
        )

        #expect(manager.shortcutSummary == "Not configured")
        #expect(!manager.hasConfiguredShortcut)
    }

    @Test func updateShortcutSummaryTracksConfiguredState() {
        let rig = CueAppModelTestRig()
        let bindingService = FakeHotkeyBindingService(shortcut: defaultPushToTalkShortcut)
        let manager = CueHotkeyManager(appModel: rig.model, bindingService: bindingService)
        let updatedShortcut = KeyboardShortcuts.Shortcut(.d, modifiers: [.shift, .option])

        manager.updateShortcutSummary(nil)
        #expect(manager.shortcutSummary == "Not configured")
        #expect(!manager.hasConfiguredShortcut)

        manager.updateShortcutSummary(updatedShortcut)
        #expect(manager.shortcutSummary == updatedShortcut.description)
        #expect(manager.hasConfiguredShortcut)
    }

    @Test func registeredKeyHandlersDrivePushToTalkWorkflow() async {
        let rig = CueAppModelTestRig()
        let model = rig.model
        let bindingService = FakeHotkeyBindingService(shortcut: defaultPushToTalkShortcut)

        await model.launch()
        let manager = CueHotkeyManager(
            appModel: model,
            bindingService: bindingService
        )

        _ = manager
        bindingService.triggerKeyDown()
        await yieldUntil { rig.transcriptionService.startRecordingCallCount == 1 }

        #expect(model.state.session == .recording)
        #expect(rig.soundService.playRecordingStartedCallCount == 1)

        bindingService.triggerKeyUp()
        await yieldUntil { rig.insertionService.insertCallCount == 1 }

        #expect(rig.transcriptionService.stopRecordingCallCount == 1)
        #expect(model.state.session == .idle)
        #expect(rig.insertionService.insertedTexts == [rig.transcriptionService.result])
        #expect(rig.soundService.playRecordingStoppedCallCount == 1)
    }

    @Test func immediateKeyUpWaitsForSuspendedRecordingStart() async {
        let rig = CueAppModelTestRig()
        rig.transcriptionService.suspendsStartRecording = true
        let model = rig.model
        let bindingService = FakeHotkeyBindingService(shortcut: defaultPushToTalkShortcut)

        await model.launch()
        let manager = CueHotkeyManager(
            appModel: model,
            bindingService: bindingService
        )

        _ = manager
        bindingService.triggerKeyDown()
        bindingService.triggerKeyUp()
        await yieldUntil { rig.transcriptionService.startRecordingCallCount == 1 }

        rig.transcriptionService.resumeStartRecording()
        await yieldUntil { rig.insertionService.insertCallCount == 1 }

        #expect(rig.transcriptionService.stopRecordingCallCount == 1)
        #expect(model.state.session == .idle)
    }

    @Test func pressWhileTranscribingIsIgnoredInsteadOfReplayedAfterInsertion() async {
        let rig = CueAppModelTestRig()
        rig.transcriptionService.suspendsStopRecording = true
        let model = rig.model
        let bindingService = FakeHotkeyBindingService(shortcut: defaultPushToTalkShortcut)

        await model.launch()
        let manager = CueHotkeyManager(
            appModel: model,
            bindingService: bindingService
        )

        _ = manager
        bindingService.triggerKeyDown()
        await yieldUntil { model.state.session == .recording }
        bindingService.triggerKeyUp()
        await yieldUntil { rig.transcriptionService.stopRecordingCallCount == 1 }

        bindingService.triggerKeyDown()
        bindingService.triggerKeyUp()
        for _ in 0..<5 {
            await Task.yield()
        }
        rig.transcriptionService.resumeStopRecording()
        await yieldUntil { rig.insertionService.insertCallCount == 1 }

        #expect(rig.transcriptionService.startRecordingCallCount == 1)
        #expect(rig.transcriptionService.stopRecordingCallCount == 1)
        #expect(model.state.latencyMetrics?.releaseToProofOfLife ?? -1 >= 0)
        #expect(model.state.session == .idle)
    }

}

private final class FakeHotkeyBindingService: HotkeyBindingService {
    let shortcut: KeyboardShortcuts.Shortcut?
    private var eventContinuation: AsyncStream<KeyboardShortcuts.EventType>.Continuation?

    init(shortcut: KeyboardShortcuts.Shortcut?) {
        self.shortcut = shortcut
    }

    func currentShortcut() -> KeyboardShortcuts.Shortcut? {
        shortcut
    }

    func events() -> AsyncStream<KeyboardShortcuts.EventType> {
        AsyncStream { continuation in
            eventContinuation = continuation
        }
    }

    func triggerKeyDown() {
        eventContinuation?.yield(.keyDown)
    }

    func triggerKeyUp() {
        eventContinuation?.yield(.keyUp)
    }
}
