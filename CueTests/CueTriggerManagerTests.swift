import AppKit
import Foundation
import Testing
@testable import Cue

@MainActor
struct CueTriggerManagerTests {
    @Test func initializesFromBindingServiceModifier() {
        let model = CueAppModel(
            transcriptionService: FakeTranscriptionService(),
            insertionService: FakeTextInsertionService(),
            permissionService: FakePermissionService(),
            notificationCenter: NotificationCenter()
        )
        let bindingService = FakePushToTalkBindingService(modifier: .command)

        let manager = CueTriggerManager(
            appModel: model,
            bindingService: bindingService,
            notificationCenter: NotificationCenter()
        )

        #expect(manager.selectedModifier == .command)
        #expect(manager.selectedModifierTitle == "Command")
        #expect(bindingService.onPress != nil)
        #expect(bindingService.onRelease != nil)
    }

    @Test func changingSelectedModifierUpdatesBindingService() {
        let model = CueAppModel(
            transcriptionService: FakeTranscriptionService(),
            insertionService: FakeTextInsertionService(),
            permissionService: FakePermissionService(),
            notificationCenter: NotificationCenter()
        )
        let bindingService = FakePushToTalkBindingService(modifier: .function)
        let manager = CueTriggerManager(
            appModel: model,
            bindingService: bindingService,
            notificationCenter: NotificationCenter()
        )

        manager.selectedModifier = .option

        #expect(bindingService.modifier == .option)
        #expect(bindingService.setModifierCalls == [.option])
    }

    @Test func appActivationRefreshesMonitoring() {
        let appNotificationCenter = NotificationCenter()
        let model = CueAppModel(
            transcriptionService: FakeTranscriptionService(),
            insertionService: FakeTextInsertionService(),
            permissionService: FakePermissionService(),
            notificationCenter: NotificationCenter()
        )
        let bindingService = FakePushToTalkBindingService()
        let manager = CueTriggerManager(
            appModel: model,
            bindingService: bindingService,
            notificationCenter: appNotificationCenter
        )

        appNotificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        _ = manager
        #expect(bindingService.refreshMonitoringCallCount == 1)
    }
}
