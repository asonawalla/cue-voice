import Foundation
import Testing
@testable import Cue

@MainActor
struct CueAppModelDictationTests {
    @Test func handlePushToTalkReleasedStoresTranscriptAndPasteAttemptResult() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService()
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
    }

    @Test func launchFailureMovesStateToErrorWhenPermissionsAreSatisfied() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let permissionService = FakePermissionService()
        transcriptionService.prepareError = CueError.modelDownloadFailed("offline")

        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
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
        transcriptionService.stopRecordingError = CueError.transcriptionFailed("backend offline")
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService,
            permissionService: permissionService,
            notificationCenter: NotificationCenter()
        )

        await model.launch()
        await model.handlePushToTalkPressed()
        await model.handlePushToTalkReleased()

        #expect(model.errorMessage == "Cue could not transcribe the recording: backend offline")
        #expect(insertionService.insertCallCount == 0)
    }
}
