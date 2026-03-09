import Foundation
import Testing
@testable import Cue

@MainActor
struct CueAppModelDictationTests {
    @Test func handlePushToTalkReleasedStoresTranscriptAndPasteAttemptResult() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService()
        let soundService = FakeSoundService()
        transcriptionService.result = CueTranscriptionResult(
            text: "milestone three transcript",
            language: "en",
            recordingDuration: 2.0,
            modelLoadDuration: 0.25,
            pipelineDuration: 0.5
        )
        insertionService.result = CueInsertionResult(
            delivery: .pasteCommandSent,
            targetAppName: "TextEdit",
            targetBundleIdentifier: "com.apple.TextEdit",
            pasteDuration: 0.18
        )

        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            soundService: soundService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()
        await model.handlePushToTalkPressed()
        await model.handlePushToTalkReleased()

        #expect(model.sessionState == .idle)
        #expect(model.transcript == "milestone three transcript")
        #expect(model.lastInsertionResult == insertionService.result)
        #expect(model.latencyMetrics != nil)
        #expect(model.latencyMetrics?.recordingDuration == 2.0)
        #expect(model.latencyMetrics?.pasteDuration == 0.18)
        #expect((model.latencyMetrics?.totalDuration ?? 0) >= 2.18)
        #expect(transcriptionService.startRecordingCallCount == 1)
        #expect(transcriptionService.stopRecordingCallCount == 1)
        #expect(insertionService.insertCallCount == 1)
        #expect(soundService.playRecordingStartedCallCount == 1)
        #expect(soundService.playRecordingStoppedCallCount == 1)
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

        #expect(model.errorMessage == "Cue could not prepare the base.en model: offline")
        #expect(insertionService.insertCallCount == 0)
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
        await model.handlePushToTalkPressed()
        await model.handlePushToTalkReleased()

        #expect(model.errorMessage == "Cue could not transcribe the recording: backend offline")
        #expect(insertionService.insertCallCount == 0)
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
        await model.handlePushToTalkPressed()

        #expect(soundService.playRecordingStartedCallCount == 1)
        #expect(model.errorMessage == "Cue could not start recording: audio device busy")
        #expect(model.sessionState == .failed(CueFailure.from(CueError.recordingFailed("audio device busy"))))
    }
}

@MainActor
struct SystemSoundServiceTests {
    @Test func cuePlaybackRestartsTheDedicatedSoundInstanceEachTime() async throws {
        let recordingStartedSound = FakePlayableSound()
        let recordingStoppedSound = FakePlayableSound()
        let service = SystemSoundService(
            recordingStartedSound: recordingStartedSound,
            recordingStoppedSound: recordingStoppedSound
        )

        service.playRecordingStarted()
        service.playRecordingStarted()
        service.playRecordingStopped()

        #expect(recordingStartedSound.stopCallCount == 2)
        #expect(recordingStartedSound.playCallCount == 2)
        #expect(recordingStoppedSound.stopCallCount == 1)
        #expect(recordingStoppedSound.playCallCount == 1)
    }
}
