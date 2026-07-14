import AppKit
import Foundation
import Testing
@testable import Cue

@MainActor
struct CueAppModelLifecycleTests {
    @Test func launchWithGrantedPermissionsWarmsTheModelWithoutLeavingIdle() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService()
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()

        #expect(transcriptionService.prepareCallCount == 1)
        #expect(model.state.session == .idle)
        #expect(model.state.permissions.isFullyConfigured)
        #expect(model.state.modelStatus.isReady)
        #expect(!model.presentation.needsPermissionPrompt)
        #expect(model.presentation.errorMessage == nil)
        #expect(insertionService.insertCallCount == 0)
    }

    @Test func launchWithMissingMicrophoneSkipsModelWarmupAndStaysIdle() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .notDetermined, accessibility: .notGranted)
        )
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()

        #expect(!model.state.permissions.isFullyConfigured)
        #expect(transcriptionService.prepareCallCount == 0)
        #expect(model.state.session == .idle)
        #expect(model.presentation.needsPermissionPrompt)
    }

    @Test func launchWithMissingAccessibilitySkipsModelWarmupAndNeedsSetupPrompt() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .granted, accessibility: .notGranted)
        )
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()

        #expect(!model.state.permissions.isFullyConfigured)
        #expect(transcriptionService.prepareCallCount == 0)
        #expect(model.state.session == .idle)
        #expect(model.presentation.needsPermissionPrompt)
        #expect(model.presentation.menuBarPrimaryStatus == "Accessibility Required")
    }

    @Test func becomingActiveRefreshesPermissionsAndWarmsModel() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService(
            snapshot: CuePermissionSnapshot(microphone: .granted, accessibility: .notGranted)
        )
        let notificationCenter = NotificationCenter()
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: notificationCenter
        )

        await model.launch()

        #expect(transcriptionService.prepareCallCount == 0)
        #expect(!model.state.permissions.isFullyConfigured)

        permissionService.snapshot = CuePermissionSnapshot(microphone: .granted, accessibility: .granted)
        notificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        await yieldUntil { transcriptionService.prepareCallCount == 1 }

        #expect(model.state.permissions.isFullyConfigured)
        #expect(model.state.modelStatus.isReady)
        #expect(model.state.session == .idle)
    }

    @Test func debugCaptureTogglePersistsAcrossModelInstances() async throws {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstModel = CueAppModel(
            transcriptionService: FakeTranscriptionService(),
            insertionService: FakeTextInsertionService(),
            permissionService: FakePermissionService(),
            defaults: defaults,
            notificationCenter: NotificationCenter()
        )

        #expect(!firstModel.debugCapturesEnabled)

        firstModel.debugCapturesEnabled = true

        let secondModel = CueAppModel(
            transcriptionService: FakeTranscriptionService(),
            insertionService: FakeTextInsertionService(),
            permissionService: FakePermissionService(),
            defaults: defaults,
            notificationCenter: NotificationCenter()
        )

        #expect(secondModel.debugCapturesEnabled)
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
