import Foundation
import Testing
@testable import Cue

@MainActor
struct CueAppModelDictationTests {
    @Test func handlePushToTalkReleasedInsertsTranscriptAndStoresVisibleMetrics() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService()
        let soundService = FakeSoundService()
        transcriptionService.result = "milestone three transcript"
        insertionService.result = CueInsertionResult(
            pasteDuration: 0.18,
            pasteCommandPostedAt: Date()
        )

        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            soundService: soundService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()
        model.handlePushToTalkPressed()
        await yieldUntil { model.state.session == .recording }
        model.handlePushToTalkReleased()
        await yieldUntil { insertionService.insertCallCount == 1 }

        #expect(model.state.session == .idle)
        #expect(insertionService.insertedTexts == ["milestone three transcript"])
        #expect(model.state.latencyMetrics != nil)
        #expect(model.state.latencyMetrics?.pasteDuration == 0.18)
        #expect(transcriptionService.startRecordingCallCount == 1)
        #expect(transcriptionService.stopRecordingCallCount == 1)
        #expect(insertionService.insertCallCount == 1)
        #expect(soundService.playRecordingStartedCallCount == 1)
        #expect(soundService.playRecordingStoppedCallCount == 1)
    }

    @Test func releaseWhileRecordingStartIsSuspendedStillStopsAndInserts() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        transcriptionService.suspendsStartRecording = true
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: FakePermissionService(),
            soundService: FakeSoundService(),
            notificationCenter: NotificationCenter()
        )

        await model.launch()
        model.handlePushToTalkPressed()
        await yieldUntil { transcriptionService.startRecordingCallCount == 1 }

        model.handlePushToTalkReleased()
        transcriptionService.resumeStartRecording()
        await yieldUntil { insertionService.insertCallCount == 1 }

        #expect(transcriptionService.stopRecordingCallCount == 1)
        #expect(insertionService.insertedTexts == [transcriptionService.result])
        #expect(model.state.session == .idle)
    }

    @Test func launchFailureMovesStateToErrorWhenPermissionsAreSatisfied() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService()
        let soundService = FakeSoundService()
        transcriptionService.prepareError = CueError.modelDownloadFailed("offline")

        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            soundService: soundService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()

        #expect(model.presentation.errorMessage == "Cue could not prepare the small.en model: offline")
        #expect(insertionService.insertCallCount == 0)
        #expect(soundService.playErrorCallCount == 0)
    }

    @Test func transcriptionFailureDoesNotAttemptPaste() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService()
        let soundService = FakeSoundService()
        transcriptionService.stopRecordingError = CueError.transcriptionFailed("backend offline")
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            soundService: soundService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()
        model.handlePushToTalkPressed()
        await yieldUntil { model.state.session == .recording }
        model.handlePushToTalkReleased()
        await yieldUntil { model.state.currentFailure != nil }

        #expect(model.presentation.errorMessage == "Cue could not transcribe the recording: backend offline")
        #expect(insertionService.insertCallCount == 0)
        #expect(soundService.playRecordingStartedCallCount == 1)
        #expect(soundService.playRecordingStoppedCallCount == 1)
        #expect(soundService.playErrorCallCount == 1)
    }

    @Test func startCuePlaysImmediatelyWhenAnAcceptedStartAttemptLaterFails() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService()
        let soundService = FakeSoundService()
        transcriptionService.startRecordingError = CueError.recordingFailed("audio device busy")

        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            soundService: soundService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()
        model.handlePushToTalkPressed()
        await yieldUntil { model.state.currentFailure != nil }

        #expect(soundService.playRecordingStartedCallCount == 1)
        #expect(soundService.playErrorCallCount == 1)
        #expect(model.presentation.errorMessage == "Cue could not start recording: audio device busy")
        #expect(model.state.session == .failed(CueFailure.from(CueError.recordingFailed("audio device busy"))))
    }

    @Test func pasteFailurePlaysErrorSound() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService()
        let soundService = FakeSoundService()
        insertionService.insertError = CueError.pasteFailed("event bridge down")

        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            soundService: soundService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()
        model.handlePushToTalkPressed()
        await yieldUntil { model.state.session == .recording }
        model.handlePushToTalkReleased()
        await yieldUntil { model.state.currentFailure != nil }

        #expect(soundService.playRecordingStartedCallCount == 1)
        #expect(soundService.playRecordingStoppedCallCount == 1)
        #expect(soundService.playErrorCallCount == 1)
        #expect(model.presentation.errorMessage == "Cue could not paste the transcript: event bridge down")
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

@MainActor
struct SystemSoundServiceTests {
    @Test func cuePlaybackRestartsTheDedicatedSoundInstanceEachTime() async throws {
        let recordingStartedSound = FakePlayableSound()
        let recordingStoppedSound = FakePlayableSound()
        let errorSound = FakePlayableSound()
        let service = SystemSoundService(
            recordingStartedSound: recordingStartedSound,
            recordingStoppedSound: recordingStoppedSound,
            errorSound: errorSound
        )

        service.playRecordingStarted()
        service.playRecordingStarted()
        service.playRecordingStopped()
        service.playError()

        #expect(recordingStartedSound.stopCallCount == 2)
        #expect(recordingStartedSound.playCallCount == 2)
        #expect(recordingStoppedSound.stopCallCount == 1)
        #expect(recordingStoppedSound.playCallCount == 1)
        #expect(errorSound.stopCallCount == 1)
        #expect(errorSound.playCallCount == 1)
    }
}
