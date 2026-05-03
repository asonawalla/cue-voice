import AppKit
import Foundation
import Testing
@testable import Cue

@MainActor
struct CueAppStateReducerTests {
    @Test func permissionRefreshClearsOnlyResolvedPermissionFailure() {
        var state = CueAppState.initial(
            permissionSnapshot: CuePermissionSnapshot(microphone: .denied, accessibility: .notGranted)
        )
        state.apply(.failurePresented(CueFailure.from(CueError.accessibilityPermissionDenied)))

        state.apply(
            .permissionsRefreshed(CuePermissionSnapshot(microphone: .granted, accessibility: .notGranted))
        )

        #expect(state.session == .failed(CueFailure.from(CueError.accessibilityPermissionDenied)))

        state.apply(
            .permissionsRefreshed(CuePermissionSnapshot(microphone: .granted, accessibility: .granted))
        )

        #expect(state.session == .idle)
    }

    @Test func modelPreparationSuccessClearsOnlyModelFailure() {
        var state = CueAppState.initial(
            permissionSnapshot: CuePermissionSnapshot(microphone: .granted, accessibility: .granted)
        )
        state.apply(.failurePresented(CueFailure.from(CueError.modelDownloadFailed("offline"))))

        state.apply(.modelPreparationSucceeded)

        #expect(state.session == .idle)

        state.apply(.failurePresented(CueFailure.from(CueError.emptyTranscript)))
        state.apply(.modelPreparationSucceeded)

        #expect(state.session == .failed(CueFailure.from(CueError.emptyTranscript)))
    }

    @Test func dictationSuccessPathStoresTranscriptInsertionMetricsAndReturnsToIdle() {
        var state = CueAppState.initial(
            permissionSnapshot: CuePermissionSnapshot(microphone: .granted, accessibility: .granted)
        )
        let transcriptionResult = CueTranscriptionResult(
            text: "centralized transition",
            language: "en",
            recordingDuration: 1.25,
            modelLoadDuration: 0.1,
            pipelineDuration: 0.3
        )
        let insertionResult = CueInsertionResult(
            delivery: .pasteCommandSent,
            targetAppName: "TextEdit",
            targetBundleIdentifier: "com.apple.TextEdit",
            pasteDuration: 0.2,
            clipboardRestoreState: .restored,
            pasteCommandPostedAt: Date()
        )
        let metrics = LatencyMetrics(
            recordingDuration: 1.25,
            transcriptionDuration: 0.4,
            pasteDuration: 0.2,
            totalDuration: 1.85,
            modelLoadDuration: 0.1,
            backendPipelineDuration: 0.3,
            pressToAck: 0.01,
            releaseToProofOfLife: 0.02,
            releaseToInsert: 0.6
        )

        state.apply(.recordingStarted)
        state.apply(.transcriptionStarted)
        state.apply(.transcriptionCompleted(transcriptionResult))
        state.apply(.insertionCompleted(insertionResult, metrics))

        #expect(state.session == .idle)
        #expect(state.transcript == "centralized transition")
        #expect(state.lastInsertionResult == insertionResult)
        #expect(state.latencyMetrics == metrics)
    }

    @Test func dictationAttemptClearsStaleFailureAndMetrics() {
        var state = CueAppState.initial(
            permissionSnapshot: CuePermissionSnapshot(microphone: .granted, accessibility: .granted)
        )
        state.latencyMetrics = LatencyMetrics(
            recordingDuration: 1,
            transcriptionDuration: 2,
            pasteDuration: 3,
            totalDuration: 6,
            modelLoadDuration: 0.1,
            backendPipelineDuration: 0.2,
            pressToAck: 0.01,
            releaseToProofOfLife: 0.02,
            releaseToInsert: 0.03
        )
        state.apply(.failurePresented(CueFailure.from(CueError.emptyTranscript)))

        state.apply(.dictationAttemptStarted)

        #expect(state.session == .idle)
        #expect(state.latencyMetrics == nil)
    }
}

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
        #expect(model.sessionState == .idle)
        #expect(model.isReadyToRecord)
        #expect(model.isModelReady)
        #expect(!model.needsPermissionPrompt)
        #expect(model.errorMessage == nil)
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

        #expect(!model.isReadyToRecord)
        #expect(transcriptionService.prepareCallCount == 0)
        #expect(model.sessionState == .idle)
        #expect(model.needsPermissionPrompt)
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

        #expect(!model.isReadyToRecord)
        #expect(transcriptionService.prepareCallCount == 0)
        #expect(model.sessionState == .idle)
        #expect(model.needsPermissionPrompt)
        #expect(model.menuBarPrimaryStatus == "Accessibility Required")
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
        #expect(!model.isReadyToRecord)

        permissionService.snapshot = CuePermissionSnapshot(microphone: .granted, accessibility: .granted)
        notificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        await yieldUntil { transcriptionService.prepareCallCount == 1 }

        #expect(model.isReadyToRecord)
        #expect(model.isModelReady)
        #expect(model.sessionState == .idle)
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
