import Foundation
import Testing
@testable import Cue

@MainActor
struct CueTests {
    @Test func launchWarmsTheModelWithoutLeavingIdle() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService
        )

        await model.launch()

        #expect(transcriptionService.prepareCallCount == 1)
        #expect(model.phase == .idle)
        #expect(model.isModelReady)
        #expect(model.errorMessage == nil)
        #expect(insertionService.insertCallCount == 0)
    }

    @Test func handlePushToTalkPressedStartsRecordingWhenModelIsReady() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService
        )

        await model.launch()
        await model.handlePushToTalkPressed()

        #expect(model.phase == .recording)
        #expect(transcriptionService.startRecordingCallCount == 1)
        #expect(insertionService.insertCallCount == 0)
    }

    @Test func handlePushToTalkReleasedStoresTranscriptPastesAndReturnsToIdle() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        transcriptionService.result = CueTranscriptionResult(
            text: "milestone two transcript",
            language: "en",
            recordingDuration: 2.0,
            modelLoadDuration: 0.25,
            pipelineDuration: 0.5
        )
        insertionService.result = CueInsertionResult(
            targetAppName: "TextEdit",
            targetBundleIdentifier: "com.apple.TextEdit",
            pasteDuration: 0.18,
            clipboardRestoreOutcome: .restored
        )
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService
        )

        await model.launch()
        await model.handlePushToTalkPressed()
        await model.handlePushToTalkReleased()

        #expect(model.phase == .idle)
        #expect(model.transcript == "milestone two transcript")
        #expect(model.lastInsertionResult == insertionService.result)
        #expect(model.latencyMetrics != nil)
        #expect(model.latencyMetrics?.recordingDuration == 2.0)
        #expect(model.latencyMetrics?.pasteDuration == 0.18)
        #expect((model.latencyMetrics?.totalDuration ?? 0) >= 2.18)
        #expect(transcriptionService.startRecordingCallCount == 1)
        #expect(transcriptionService.stopRecordingCallCount == 1)
        #expect(insertionService.insertCallCount == 1)
    }

    @Test func launchFailureMovesStateToError() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        transcriptionService.prepareError = CueError.modelDownloadFailed("offline")

        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService
        )

        await model.launch()

        #expect(model.phase == .error)
        #expect(model.errorMessage == "Cue could not prepare the base.en model: offline")
        #expect(insertionService.insertCallCount == 0)
    }

    @Test func pushToTalkPressDoesNothingBeforeModelIsReady() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService
        )

        await model.handlePushToTalkPressed()

        #expect(model.phase == .idle)
        #expect(transcriptionService.startRecordingCallCount == 0)
        #expect(transcriptionService.prepareCallCount == 0)
        #expect(insertionService.insertCallCount == 0)
    }

    @Test func pasteFailurePreservesTranscriptAndMovesStateToError() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        insertionService.insertError = CueError.pastePermissionDenied
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService
        )

        await model.launch()
        await model.handlePushToTalkPressed()
        await model.handlePushToTalkReleased()

        #expect(model.phase == .error)
        #expect(model.transcript == transcriptionService.result.text)
        #expect(model.errorMessage == CueError.pastePermissionDenied.errorDescription)
        #expect(model.shouldOfferPastePermissionRecovery)
        #expect(model.latencyMetrics == nil)
        #expect(insertionService.insertCallCount == 1)
    }

    @Test func transcriptionFailureDoesNotAttemptPaste() async throws {
        let transcriptionService = FakeTranscriptionService()
        let insertionService = FakeTextInsertionService()
        transcriptionService.stopRecordingError = CueError.transcriptionFailed("backend offline")
        let model = CueAppModel(
            transcriptionService: transcriptionService,
            insertionService: insertionService
        )

        await model.launch()
        await model.handlePushToTalkPressed()
        await model.handlePushToTalkReleased()

        #expect(model.phase == .error)
        #expect(model.errorMessage == "Cue could not transcribe the recording: backend offline")
        #expect(insertionService.insertCallCount == 0)
    }
}

@MainActor
private final class FakeTranscriptionService: TranscriptionService {
    var statusHandler: ((ModelPreparationStatus) -> Void)?

    var prepareCallCount = 0
    var startRecordingCallCount = 0
    var stopRecordingCallCount = 0
    var prepareError: Error?
    var stopRecordingError: Error?
    var result = CueTranscriptionResult(
        text: "milestone two transcript",
        language: "en",
        recordingDuration: 1.5,
        modelLoadDuration: 0.25,
        pipelineDuration: 0.5
    )

    func prepareModel() async throws {
        prepareCallCount += 1

        if let prepareError {
            throw prepareError
        }

        statusHandler?(.ready)
    }

    func startRecording() async throws {
        startRecordingCallCount += 1
    }

    func stopRecording() async throws -> CueTranscriptionResult {
        stopRecordingCallCount += 1

        if let stopRecordingError {
            throw stopRecordingError
        }

        return result
    }
}

@MainActor
private final class FakeTextInsertionService: TextInsertionService {
    var insertCallCount = 0
    var insertError: Error?
    var result = CueInsertionResult(
        targetAppName: "TextEdit",
        targetBundleIdentifier: "com.apple.TextEdit",
        pasteDuration: 0.12,
        clipboardRestoreOutcome: .restored
    )

    func insert(_ text: String) async throws -> CueInsertionResult {
        insertCallCount += 1

        if let insertError {
            throw insertError
        }

        return result
    }
}
