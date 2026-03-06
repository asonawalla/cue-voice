import Foundation
import Testing
@testable import Cue

@MainActor
struct CueTests {
    @Test func launchWarmsTheModelWithoutLeavingIdle() async throws {
        let transcriptionService = FakeTranscriptionService()
        let model = CueAppModel(transcriptionService: transcriptionService)

        await model.launch()

        #expect(transcriptionService.prepareCallCount == 1)
        #expect(model.phase == .idle)
        #expect(model.isModelReady)
        #expect(model.errorMessage == nil)
    }

    @Test func handlePushToTalkPressedStartsRecordingWhenModelIsReady() async throws {
        let transcriptionService = FakeTranscriptionService()
        let model = CueAppModel(transcriptionService: transcriptionService)

        await model.launch()
        await model.handlePushToTalkPressed()

        #expect(model.phase == .recording)
        #expect(transcriptionService.startRecordingCallCount == 1)
    }

    @Test func handlePushToTalkReleasedStoresTranscriptAndReturnsToIdle() async throws {
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.result = CueTranscriptionResult(
            text: "milestone two transcript",
            language: "en",
            recordingDuration: 2.0,
            modelLoadDuration: 0.25,
            pipelineDuration: 0.5
        )
        let model = CueAppModel(transcriptionService: transcriptionService)

        await model.launch()
        await model.handlePushToTalkPressed()
        await model.handlePushToTalkReleased()

        #expect(model.phase == .idle)
        #expect(model.transcript == "milestone two transcript")
        #expect(model.latencyMetrics != nil)
        #expect(model.latencyMetrics?.recordingDuration == 2.0)
        #expect(model.latencyMetrics?.totalDuration ?? 0 >= 2.0)
        #expect(transcriptionService.startRecordingCallCount == 1)
        #expect(transcriptionService.stopRecordingCallCount == 1)
    }

    @Test func launchFailureMovesStateToError() async throws {
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.prepareError = CueError.modelDownloadFailed("offline")

        let model = CueAppModel(transcriptionService: transcriptionService)

        await model.launch()

        #expect(model.phase == .error)
        #expect(model.errorMessage == "Cue could not prepare the base.en model: offline")
    }

    @Test func pushToTalkPressDoesNothingBeforeModelIsReady() async throws {
        let transcriptionService = FakeTranscriptionService()
        let model = CueAppModel(transcriptionService: transcriptionService)

        await model.handlePushToTalkPressed()

        #expect(model.phase == .idle)
        #expect(transcriptionService.startRecordingCallCount == 0)
        #expect(transcriptionService.prepareCallCount == 0)
    }
}

@MainActor
private final class FakeTranscriptionService: TranscriptionService {
    var statusHandler: ((ModelPreparationStatus) -> Void)?

    var prepareCallCount = 0
    var startRecordingCallCount = 0
    var stopRecordingCallCount = 0
    var prepareError: Error?
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
        return result
    }
}
