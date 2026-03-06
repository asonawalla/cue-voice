import Foundation
import Testing
@testable import Cue

@MainActor
struct CueTests {
    @Test func prepareModelTransitionsBackToIdleWhenReady() async throws {
        let transcriptionService = FakeTranscriptionService()
        let model = CueAppModel(transcriptionService: transcriptionService)

        await model.prepareModel()

        #expect(transcriptionService.prepareCallCount == 1)
        #expect(model.phase == .idle)
        #expect(model.isModelReady)
        #expect(model.errorMessage == nil)
    }

    @Test func stopRecordingStoresTranscriptAndMetrics() async throws {
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.result = CueTranscriptionResult(
            text: "phase one transcript",
            language: "en",
            recordingDuration: 2.0,
            modelLoadDuration: 0.25,
            pipelineDuration: 0.5
        )
        let model = CueAppModel(transcriptionService: transcriptionService)

        await model.prepareModel()
        await model.startRecording()
        await model.stopRecording()

        #expect(model.phase == .completed)
        #expect(model.transcript == "phase one transcript")
        #expect(model.latencyMetrics != nil)
        #expect(model.latencyMetrics?.recordingDuration == 2.0)
        #expect(model.latencyMetrics?.totalDuration ?? 0 >= 2.0)
        #expect(transcriptionService.startRecordingCallCount == 1)
        #expect(transcriptionService.stopRecordingCallCount == 1)
    }

    @Test func prepareModelFailureMovesStateToError() async throws {
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.prepareError = CueError.modelDownloadFailed("offline")

        let model = CueAppModel(transcriptionService: transcriptionService)

        await model.prepareModel()

        #expect(model.phase == .error)
        #expect(model.errorMessage == "Cue could not prepare the base.en model: offline")
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
        text: "phase one transcript",
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
