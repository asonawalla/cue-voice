import AppKit
import Foundation
import Testing
@testable import Cue

@MainActor
struct CueAppModelLifecycleTests {
    @Test func launchWithGrantedPermissionsWarmsTheModelWithoutLeavingIdle() async {
        let rig = CueAppModelTestRig()
        let model = rig.model

        await model.launch()

        #expect(rig.transcriptionService.prepareCallCount == 1)
        #expect(model.state.session == .idle)
        #expect(model.state.permissions.isFullyConfigured)
        #expect(model.state.modelStatus.isReady)
        #expect(!model.presentation.needsPermissionPrompt)
        #expect(model.presentation.errorMessage == nil)
        #expect(rig.insertionService.insertCallCount == 0)
    }

    @Test func launchWithMissingMicrophoneSkipsModelWarmupAndStaysIdle() async {
        let rig = CueAppModelTestRig(
            permissions: CuePermissionSnapshot(microphone: .notDetermined, accessibility: .notGranted)
        )
        let model = rig.model

        await model.launch()

        #expect(!model.state.permissions.isFullyConfigured)
        #expect(rig.transcriptionService.prepareCallCount == 0)
        #expect(model.state.session == .idle)
        #expect(model.presentation.needsPermissionPrompt)
    }

    @Test func launchWithMissingAccessibilitySkipsModelWarmupAndNeedsSetupPrompt() async {
        let rig = CueAppModelTestRig(
            permissions: CuePermissionSnapshot(microphone: .granted, accessibility: .notGranted)
        )
        let model = rig.model

        await model.launch()

        #expect(!model.state.permissions.isFullyConfigured)
        #expect(rig.transcriptionService.prepareCallCount == 0)
        #expect(model.state.session == .idle)
        #expect(model.presentation.needsPermissionPrompt)
        #expect(model.presentation.status.primary == "Accessibility Required")
    }

    @Test func becomingActiveRefreshesPermissionsAndWarmsModel() async {
        let rig = CueAppModelTestRig(
            permissions: CuePermissionSnapshot(microphone: .granted, accessibility: .notGranted)
        )
        let model = rig.model

        await model.launch()

        #expect(rig.transcriptionService.prepareCallCount == 0)
        #expect(!model.state.permissions.isFullyConfigured)

        rig.permissionService.snapshot = CuePermissionSnapshot(microphone: .granted, accessibility: .granted)
        rig.notificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        await yieldUntil { rig.transcriptionService.prepareCallCount == 1 }

        #expect(model.state.permissions.isFullyConfigured)
        #expect(model.state.modelStatus.isReady)
        #expect(model.state.session == .idle)
    }

    @Test func debugCaptureTogglePersistsAcrossModelInstances() {
        let rig = CueAppModelTestRig()
        let firstModel = rig.model

        #expect(!firstModel.debugCapturesEnabled)

        firstModel.debugCapturesEnabled = true

        let secondModel = rig.makeModel()

        #expect(secondModel.debugCapturesEnabled)
    }
}
