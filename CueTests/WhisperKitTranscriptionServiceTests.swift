import Foundation
import Testing
import WhisperKit
@testable import Cue

@MainActor
struct WhisperKitTranscriptionServiceTests {
    @Test func prepareModelUsesCachedPathWithoutDownloading() async throws {
        let rig = WhisperKitServiceTestRig()
        let cachedModelFolder = rig.downloadedModelFolder()
        try FileManager.default.createDirectory(at: cachedModelFolder, withIntermediateDirectories: true)
        rig.defaults.set(cachedModelFolder.path, forKey: CueAppConfiguration.cachedModelPathDefaultsKey)

        let factory = FakeWhisperKitClientFactory(downloadResult: cachedModelFolder)
        let service = rig.makeService(factory: factory)
        var statuses: [ModelPreparationStatus] = []

        try await service.prepareModel { statuses.append($0) }

        #expect(factory.downloadCallCount == 0)
        #expect(factory.makeClientCallCount == 1)
        #expect(statuses == [.checkingCache, .loading])
    }

    @Test func prepareModelUsesCurrentHardcodedModelForDownloadAndLoad() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let factory = FakeWhisperKitClientFactory(downloadResult: modelFolder)
        let service = rig.makeService(factory: factory)

        try await service.prepareModel { _ in }

        #expect(factory.downloadCallCount == 1)
        #expect(factory.downloadedVariants == [CueAppConfiguration.modelID])
        #expect(factory.makeClientModelIDs == [CueAppConfiguration.modelID])
        #expect(rig.defaults.string(forKey: CueAppConfiguration.cachedModelPathDefaultsKey) == modelFolder.path)
    }

    @Test func prepareModelIgnoresProgressCallbacksAfterDownloadFinishes() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let factory = FakeWhisperKitClientFactory(downloadResult: modelFolder)
        factory.progressToReportDuringDownload = nil
        let service = rig.makeService(factory: factory)
        var statuses: [ModelPreparationStatus] = []

        try await service.prepareModel { statuses.append($0) }

        let terminalStatuses = statuses
        #expect(terminalStatuses == [.checkingCache, .downloading(progress: nil), .loading])

        factory.capturedProgressHandler?(0.75)
        try await Task.sleep(nanoseconds: 10_000_000)

        #expect(statuses == terminalStatuses)
    }

    @Test func prepareModelIgnoresCachedPathForPreviousModelVariant() async throws {
        let rig = WhisperKitServiceTestRig()
        let staleModelFolder = rig.rootDirectory.appendingPathComponent("openai_whisper-base.en")
        try FileManager.default.createDirectory(at: staleModelFolder, withIntermediateDirectories: true)
        rig.defaults.set(staleModelFolder.path, forKey: CueAppConfiguration.cachedModelPathDefaultsKey)

        let currentModelFolder = rig.downloadedModelFolder()
        let factory = FakeWhisperKitClientFactory(downloadResult: currentModelFolder)
        let service = rig.makeService(factory: factory)

        try await service.prepareModel { _ in }

        #expect(factory.downloadCallCount == 1)
        #expect(factory.downloadedVariants == [CueAppConfiguration.modelID])
        #expect(factory.makeClientModelIDs == [CueAppConfiguration.modelID])
        #expect(rig.defaults.string(forKey: CueAppConfiguration.cachedModelPathDefaultsKey) == currentModelFolder.path)
    }

    @Test func prepareModelReportsLoadFailuresSeparatelyFromDownloadFailures() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let factory = FakeWhisperKitClientFactory(downloadResult: modelFolder)
        factory.makeClientError = NSError(domain: "CueTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "bad weights"])
        let service = rig.makeService(factory: factory)

        await #expect(throws: CueError.modelLoadFailed("bad weights")) {
            try await service.prepareModel { _ in }
        }
    }

    @Test func stopRecordingBuildsResultFromClientSegments() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        client.transcriptions = [
            WhisperKitTranscriptionSegment(text: "hello ", language: "en", modelLoadDuration: 0.2, pipelineDuration: 0.4),
            WhisperKitTranscriptionSegment(text: "world", language: "en", modelLoadDuration: 0.4, pipelineDuration: 0.6)
        ]
        let factory = FakeWhisperKitClientFactory(downloadResult: modelFolder, client: client)
        let service = rig.makeService(factory: factory)

        try await service.prepareModel { _ in }
        try await service.startRecording()
        let result = try await service.stopRecording(saveDebugCapture: false)

        #expect(client.startRecordingCallCount == 1)
        #expect(client.stopRecordingCallCount == 1)
        #expect(factory.makeClientCallCount == 1)
        #expect(result == "hello world")
    }

    @Test func preparingRecordingPreviewLazilyCreatesAndCachesASeparateClient() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let primaryClient = FakeWhisperKitClient()
        let previewClient = FakeWhisperKitClient()
        let factory = FakeWhisperKitClientFactory(
            downloadResult: modelFolder,
            client: primaryClient,
            previewClient: previewClient
        )
        let service = rig.makeService(factory: factory)

        try await service.prepareModel { _ in }
        await service.prepareRecordingPreview()
        await service.prepareRecordingPreview()

        #expect(factory.makeClientCallCount == 2)
    }

    @Test func streamingDecodingStartsAtTheConfirmedSuffixAndKeepsTimestamps() {
        let options = WhisperKitStreamingDecodingConfiguration.makeOptions(startingAt: 1.25)

        #expect(options.clipTimestamps == [1.25])
        #expect(options.skipSpecialTokens)
        #expect(!options.withoutTimestamps)
        #expect(options.windowClipTime == 0)
    }

    @Test func recordingPreviewVoiceActivityDetectsQuietSpeechBelowWhisperKitDefault() {
        let quietSpeech = (0 ..< 8_000).map { index in
            index.isMultiple(of: 2) ? Float(0.006) : Float(-0.006)
        }

        #expect(RecordingPreviewVoiceActivityDetector.hasVoiceActivity(in: quietSpeech))
    }

    @Test func recordingPreviewVoiceActivityRejectsLowBackgroundNoise() {
        let backgroundNoise = (0 ..< 8_000).map { index in
            index.isMultiple(of: 2) ? Float(0.003) : Float(-0.003)
        }

        #expect(!RecordingPreviewVoiceActivityDetector.hasVoiceActivity(in: backgroundNoise))
    }

    @Test func disablingDuringPreviewPreparationCannotPopulateTheCacheAfterward() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let factory = FakeWhisperKitClientFactory(downloadResult: modelFolder)
        factory.suspendsPreviewClientCreation = true
        let service = rig.makeService(factory: factory)

        try await service.prepareModel { _ in }
        let preparationTask = Task {
            await service.prepareRecordingPreview()
        }
        await yieldUntil { factory.makeClientCallCount == 2 }

        await service.disableRecordingPreview()
        factory.resumePreviewClientCreation()
        await preparationTask.value

        factory.suspendsPreviewClientCreation = false
        await service.prepareRecordingPreview()

        #expect(factory.makeClientCallCount == 3)
    }

    @Test func reEnablingDuringPreviewPreparationAdoptsTheInFlightLoad() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let factory = FakeWhisperKitClientFactory(downloadResult: modelFolder)
        factory.suspendsPreviewClientCreation = true
        let service = rig.makeService(factory: factory)

        try await service.prepareModel { _ in }
        let firstPreparationTask = Task {
            await service.prepareRecordingPreview()
        }
        await yieldUntil { factory.makeClientCallCount == 2 }

        await service.disableRecordingPreview()
        let secondPreparationTask = Task {
            await service.prepareRecordingPreview()
        }
        await Task.yield()

        #expect(factory.makeClientCallCount == 2)

        factory.resumePreviewClientCreation()
        await firstPreparationTask.value
        await secondPreparationTask.value
        await service.prepareRecordingPreview()

        #expect(factory.makeClientCallCount == 2)
    }

    @Test func recordingPreviewPublishesOnlyACompletedHypothesisAtomically() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        let previewClient = FakeWhisperKitClient()
        previewClient.streamingOutcomes = [
            .success(streamingHypothesis("rough words arriving now"))
        ]
        previewClient.suspendsStreamingTranscription = true
        let factory = FakeWhisperKitClientFactory(
            downloadResult: modelFolder,
            client: client,
            previewClient: previewClient
        )
        let service = rig.makeService(
            factory: factory,
            previewInterval: .milliseconds(1),
            previewMinimumSampleDelta: 1
        )
        var updates: [TranscriptionPreviewUpdate] = []

        try await service.prepareModel { _ in }
        try await service.startRecording(reportPreview: { updates.append($0) })
        client.emitRecordingAudio(Array(repeating: Float(0.2), count: 20_000))
        await yieldUntil(maxYields: 2_000) { previewClient.streamingTranscribeCallCount == 1 }
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        #expect(updates.isEmpty)

        previewClient.suspendsStreamingTranscription = false
        previewClient.resumeStreamingTranscription()
        await yieldUntil(maxYields: 2_000) {
            updates == [.text("rough words arriving now")]
        }

        let result = try await service.stopRecording(saveDebugCapture: false)

        #expect(updates == [.text("rough words arriving now")])
        #expect(result == "rough words arriving now")
        #expect(previewClient.streamingTranscribeCallCount == 1)
        #expect(client.transcribeCallCount == 0)
        #expect(client.audioSamplesReadCallCount == 1)
        #expect(factory.makeClientCallCount == 2)
    }

    @Test func recordingPreviewChecksReadyAudioBeforeWaitingForPollInterval() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        let previewClient = FakeWhisperKitClient()
        client.recordingAudioEmittedDuringStart = [0.2]
        let service = rig.makeService(
            factory: FakeWhisperKitClientFactory(
                downloadResult: modelFolder,
                client: client,
                previewClient: previewClient
            ),
            previewInterval: .milliseconds(1),
            previewMinimumSampleDelta: 1
        )

        try await service.prepareModel { _ in }
        try await service.startRecording(reportPreview: { _ in })
        await yieldUntil(maxYields: 2_000) { previewClient.streamingTranscribeCallCount == 1 }

        #expect(previewClient.streamingTranscribeCallCount == 1)
        _ = try await service.stopRecording(saveDebugCapture: false)
    }

    @Test func recordingPreviewPublishesCumulativeRevisionsAsWholeStrings() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        let previewClient = FakeWhisperKitClient()
        previewClient.streamingOutcomes = [
            .success(streamingHypothesis("I sent the draft", start: 0, end: 1)),
            .success(streamingHypothesis("I sent a draft to Maya", start: 0, end: 2))
        ]
        let service = rig.makeService(
            factory: FakeWhisperKitClientFactory(
                downloadResult: modelFolder,
                client: client,
                previewClient: previewClient
            ),
            previewInterval: .milliseconds(1),
            previewMinimumSampleDelta: 1
        )
        var previews: [String] = []

        try await service.prepareModel { _ in }
        try await service.startRecording(reportPreview: { update in
            if case .text(let text) = update {
                previews.append(text)
            }
        })
        client.emitRecordingAudio(Array(repeating: Float(0.2), count: 10_000))
        await yieldUntil(maxYields: 2_000) {
            previews == ["I sent the draft"]
        }
        client.emitRecordingAudio(Array(repeating: Float(0.3), count: 10_000))
        await yieldUntil(maxYields: 2_000) {
            previews == ["I sent the draft", "I sent a draft to Maya"]
        }

        let result = try await service.stopRecording(saveDebugCapture: false)

        #expect(previews == ["I sent the draft", "I sent a draft to Maya"])
        #expect(result == "I sent a draft to Maya")
        #expect(previewClient.streamingTranscribeCallCount == 2)
        #expect(previewClient.streamingTranscribeSampleCounts == [10_000, 20_000])
        #expect(client.transcribeCallCount == 0)
    }

    @Test func wordAgreementAdvancesDecodeBoundaryWhilePublishingWholeCumulativeRevisions() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        let previewClient = FakeWhisperKitClient()
        client.audioSamples = Array(repeating: Float(0.2), count: 30_000)
        previewClient.streamingOutcomes = [
            .success(streamingWordHypothesis([
                streamingWord("I", start: 0, end: 0.3),
                streamingWord(" sent", start: 0.3, end: 0.6),
                streamingWord(" the", start: 0.6, end: 0.9),
                streamingWord(" draft", start: 0.9, end: 1.2),
                streamingWord(" today", start: 1.2, end: 1.5)
            ])),
            .success(streamingWordHypothesis([
                streamingWord("I", start: 0, end: 0.3),
                streamingWord(" sent", start: 0.3, end: 0.6),
                streamingWord(" the", start: 0.6, end: 0.9),
                streamingWord(" draft", start: 0.9, end: 1.2),
                streamingWord(" to", start: 1.2, end: 1.4),
                streamingWord(" Maya", start: 1.4, end: 1.7)
            ])),
            .success(streamingWordHypothesis([
                streamingWord(" the", start: 0.6, end: 0.9),
                streamingWord(" draft", start: 0.9, end: 1.2),
                streamingWord(" to", start: 1.2, end: 1.4),
                streamingWord(" Maya", start: 1.4, end: 1.7)
            ]))
        ]
        let service = rig.makeService(
            factory: FakeWhisperKitClientFactory(
                downloadResult: modelFolder,
                client: client,
                previewClient: previewClient
            ),
            previewInterval: .milliseconds(1),
            previewMinimumSampleDelta: 1
        )
        var previews: [String] = []

        try await service.prepareModel { _ in }
        try await service.startRecording(reportPreview: { update in
            if case .text(let text) = update {
                previews.append(text)
            }
        })
        client.emitRecordingAudio(Array(repeating: Float(0.2), count: 10_000))
        await yieldUntil(maxYields: 2_000) {
            previews == ["I sent the draft today"]
        }
        client.emitRecordingAudio(Array(repeating: Float(0.3), count: 10_000))
        await yieldUntil(maxYields: 2_000) {
            previews == ["I sent the draft today", "I sent the draft to Maya"]
        }

        let result = try await service.stopRecording(saveDebugCapture: false)

        #expect(previews == ["I sent the draft today", "I sent the draft to Maya"])
        #expect(result == "I sent the draft to Maya")
        #expect(previewClient.streamingStartingAtSeconds == [0, 0, 0.6])
        #expect(client.transcribeCallCount == 0)
    }

    @Test func finalizationCanReviseTheEntireUnconfirmedWordSuffix() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        let previewClient = FakeWhisperKitClient()
        client.audioSamples = Array(repeating: Float(0.2), count: 30_000)
        previewClient.streamingOutcomes = [
            .success(streamingWordHypothesis([
                streamingWord("I", start: 0, end: 0.2),
                streamingWord(" want", start: 0.2, end: 0.4),
                streamingWord(" to", start: 0.4, end: 0.6),
                streamingWord(" book", start: 0.6, end: 0.8),
                streamingWord(" a", start: 0.8, end: 1),
                streamingWord(" flight", start: 1, end: 1.2),
                streamingWord(" tomorrow", start: 1.2, end: 1.5)
            ])),
            .success(streamingWordHypothesis([
                streamingWord("I", start: 0, end: 0.2),
                streamingWord(" want", start: 0.2, end: 0.4),
                streamingWord(" to", start: 0.4, end: 0.6),
                streamingWord(" book", start: 0.6, end: 0.8),
                streamingWord(" the", start: 0.8, end: 1),
                streamingWord(" flight", start: 1, end: 1.2),
                streamingWord(" tomorrow", start: 1.2, end: 1.5)
            ])),
            .success(streamingWordHypothesis([
                streamingWord(" to", start: 0.4, end: 0.6),
                streamingWord(" book", start: 0.6, end: 0.8),
                streamingWord(" a", start: 0.8, end: 1),
                streamingWord(" flight", start: 1, end: 1.2),
                streamingWord(" tomorrow", start: 1.2, end: 1.5),
                streamingWord(" morning", start: 1.5, end: 1.8)
            ]))
        ]
        let service = rig.makeService(
            factory: FakeWhisperKitClientFactory(
                downloadResult: modelFolder,
                client: client,
                previewClient: previewClient
            ),
            previewInterval: .milliseconds(1),
            previewMinimumSampleDelta: 1
        )
        var previews: [String] = []

        try await service.prepareModel { _ in }
        try await service.startRecording(reportPreview: { update in
            if case .text(let text) = update {
                previews.append(text)
            }
        })
        client.emitRecordingAudio(Array(repeating: Float(0.1), count: 10_000))
        await yieldUntil(maxYields: 2_000) {
            previews == ["I want to book a flight tomorrow"]
        }
        client.emitRecordingAudio(Array(repeating: Float(0.2), count: 10_000))
        await yieldUntil(maxYields: 2_000) {
            previews == [
                "I want to book a flight tomorrow",
                "I want to book the flight tomorrow"
            ]
        }

        let result = try await service.stopRecording(saveDebugCapture: false)

        #expect(result == "I want to book a flight tomorrow morning")
        #expect(previewClient.streamingStartingAtSeconds == [0, 0, 0.4])
        #expect(client.transcribeCallCount == 0)
    }

    @Test func emptyHypothesisDoesNotCloseVoicedCoverage() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        let previewClient = FakeWhisperKitClient()
        client.audioSamples = Array(repeating: Float(0.2), count: 25_000)
        previewClient.streamingOutcomes = [
            .success(streamingWordHypothesis([
                streamingWord("I", start: 0, end: 0.3),
                streamingWord(" sent", start: 0.3, end: 0.6),
                streamingWord(" the", start: 0.6, end: 0.9),
                streamingWord(" draft", start: 0.9, end: 1.2),
                streamingWord(" today", start: 1.2, end: 1.5)
            ])),
            .success(streamingWordHypothesis([
                streamingWord("I", start: 0, end: 0.3),
                streamingWord(" sent", start: 0.3, end: 0.6),
                streamingWord(" the", start: 0.6, end: 0.9),
                streamingWord(" draft", start: 0.9, end: 1.2),
                streamingWord(" to", start: 1.2, end: 1.4),
                streamingWord(" Maya", start: 1.4, end: 1.7)
            ])),
            .success(WhisperKitStreamingHypothesis(text: "", segments: [], words: [])),
            .success(streamingWordHypothesis([
                streamingWord(" the", start: 0.6, end: 0.9),
                streamingWord(" draft", start: 0.9, end: 1.2),
                streamingWord(" to", start: 1.2, end: 1.4),
                streamingWord(" Maya", start: 1.4, end: 1.7),
                streamingWord(" now", start: 1.7, end: 1.9)
            ]))
        ]
        let service = rig.makeService(
            factory: FakeWhisperKitClientFactory(
                downloadResult: modelFolder,
                client: client,
                previewClient: previewClient
            ),
            previewInterval: .milliseconds(1),
            previewMinimumSampleDelta: 1
        )

        try await service.prepareModel { _ in }
        try await service.startRecording(reportPreview: { _ in })
        client.emitRecordingAudio(Array(repeating: Float(0.1), count: 10_000))
        await yieldUntil(maxYields: 2_000) { previewClient.streamingTranscribeCallCount == 1 }
        client.emitRecordingAudio(Array(repeating: Float(0.2), count: 10_000))
        await yieldUntil(maxYields: 2_000) { previewClient.streamingTranscribeCallCount == 2 }
        client.emitRecordingAudio(Array(repeating: Float(0.3), count: 5_000))
        await yieldUntil(maxYields: 2_000) { previewClient.streamingTranscribeCallCount == 3 }

        let result = try await service.stopRecording(saveDebugCapture: false)

        #expect(result == "I sent the draft to Maya now")
        #expect(previewClient.streamingTranscribeCallCount == 4)
        #expect(previewClient.streamingStartingAtSeconds == [0, 0, 0.6, 0.6])
        #expect(client.transcribeCallCount == 0)
    }

    @Test func unchangedHypothesisDoesNotCloseVoicedCoverage() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        let previewClient = FakeWhisperKitClient()
        client.audioSamples = Array(repeating: Float(0.2), count: 25_000)
        previewClient.streamingOutcomes = [
            .success(streamingWordHypothesis([
                streamingWord("I", start: 0, end: 0.3),
                streamingWord(" sent", start: 0.3, end: 0.6),
                streamingWord(" the", start: 0.6, end: 0.9),
                streamingWord(" draft", start: 0.9, end: 1.2),
                streamingWord(" today", start: 1.2, end: 1.5)
            ])),
            .success(streamingWordHypothesis([
                streamingWord("I", start: 0, end: 0.3),
                streamingWord(" sent", start: 0.3, end: 0.6),
                streamingWord(" the", start: 0.6, end: 0.9),
                streamingWord(" draft", start: 0.9, end: 1.2),
                streamingWord(" to", start: 1.2, end: 1.4),
                streamingWord(" Maya", start: 1.4, end: 1.7)
            ])),
            .success(streamingWordHypothesis([
                streamingWord(" the", start: 0.6, end: 0.9),
                streamingWord(" draft", start: 0.9, end: 1.2),
                streamingWord(" to", start: 1.2, end: 1.4),
                streamingWord(" Maya", start: 1.4, end: 1.7)
            ])),
            .success(streamingWordHypothesis([
                streamingWord(" to", start: 1.2, end: 1.4),
                streamingWord(" Maya", start: 1.4, end: 1.7),
                streamingWord(" now", start: 1.7, end: 1.9)
            ]))
        ]
        let service = rig.makeService(
            factory: FakeWhisperKitClientFactory(
                downloadResult: modelFolder,
                client: client,
                previewClient: previewClient
            ),
            previewInterval: .milliseconds(1),
            previewMinimumSampleDelta: 1
        )

        try await service.prepareModel { _ in }
        try await service.startRecording(reportPreview: { _ in })
        client.emitRecordingAudio(Array(repeating: Float(0.1), count: 10_000))
        await yieldUntil(maxYields: 2_000) { previewClient.streamingTranscribeCallCount == 1 }
        client.emitRecordingAudio(Array(repeating: Float(0.2), count: 10_000))
        await yieldUntil(maxYields: 2_000) { previewClient.streamingTranscribeCallCount == 2 }
        client.emitRecordingAudio(Array(repeating: Float(0.3), count: 5_000))
        await yieldUntil(maxYields: 2_000) { previewClient.streamingTranscribeCallCount == 3 }

        let result = try await service.stopRecording(saveDebugCapture: false)

        #expect(result == "I sent the draft to Maya now")
        #expect(previewClient.streamingTranscribeCallCount == 4)
        #expect(previewClient.streamingStartingAtSeconds == [0, 0, 0.6, 1.2])
        #expect(client.transcribeCallCount == 0)
    }

    @Test func revisedEarlierWordsDoNotCoverAnOmittedVoicedTail() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        let previewClient = FakeWhisperKitClient()
        client.audioSamples = Array(repeating: Float(0.2), count: 30_000)
        previewClient.streamingOutcomes = [
            .success(streamingWordHypothesis([
                streamingWord("I", start: 0, end: 0.3),
                streamingWord(" sent", start: 0.3, end: 0.6),
                streamingWord(" the", start: 0.6, end: 0.8),
                streamingWord(" draft", start: 0.8, end: 1),
                streamingWord(" today", start: 1, end: 1.2)
            ])),
            .success(streamingWordHypothesis([
                streamingWord("I", start: 0, end: 0.3),
                streamingWord(" sent", start: 0.3, end: 0.6),
                streamingWord(" the", start: 0.6, end: 0.8),
                streamingWord(" draft", start: 0.8, end: 1),
                streamingWord(" to", start: 1, end: 1.1),
                streamingWord(" Maya", start: 1.1, end: 1.2)
            ])),
            .success(streamingWordHypothesis([
                streamingWord(" the", start: 0.6, end: 0.8),
                streamingWord(" draft", start: 0.8, end: 1),
                streamingWord(" for", start: 1, end: 1.1),
                streamingWord(" Maya", start: 1.1, end: 1.2)
            ])),
            .success(streamingWordHypothesis([
                streamingWord(" the", start: 0.6, end: 0.8),
                streamingWord(" draft", start: 0.8, end: 1),
                streamingWord(" for", start: 1, end: 1.1),
                streamingWord(" Maya", start: 1.1, end: 1.2),
                streamingWord(" now", start: 1.2, end: 1.5)
            ]))
        ]
        let service = rig.makeService(
            factory: FakeWhisperKitClientFactory(
                downloadResult: modelFolder,
                client: client,
                previewClient: previewClient
            ),
            previewInterval: .milliseconds(1),
            previewMinimumSampleDelta: 1
        )

        try await service.prepareModel { _ in }
        try await service.startRecording(reportPreview: { _ in })
        client.emitRecordingAudio(Array(repeating: Float(0.1), count: 10_000))
        await yieldUntil(maxYields: 2_000) { previewClient.streamingTranscribeCallCount == 1 }
        client.emitRecordingAudio(Array(repeating: Float(0.2), count: 10_000))
        await yieldUntil(maxYields: 2_000) { previewClient.streamingTranscribeCallCount == 2 }
        client.emitRecordingAudio(Array(repeating: Float(0.3), count: 10_000))
        await yieldUntil(maxYields: 2_000) { previewClient.streamingTranscribeCallCount == 3 }

        let result = try await service.stopRecording(saveDebugCapture: false)

        #expect(result == "I sent the draft for Maya now")
        #expect(previewClient.streamingTranscribeCallCount == 4)
        #expect(previewClient.streamingStartingAtSeconds == [0, 0, 0.6, 0.6])
        #expect(client.transcribeCallCount == 0)
    }

    @Test func stopRecordingDoesNotRepeatTheWholeRecordingForASmallVoicedTail() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        let previewClient = FakeWhisperKitClient()
        client.audioSamples = Array(repeating: Float(0.2), count: 20_000)
        previewClient.streamingOutcomes = [
            .success(streamingWordHypothesis([
                streamingWord("The", start: 0, end: 0.2),
                streamingWord(" preview", start: 0.2, end: 0.5),
                streamingWord(" is", start: 0.5, end: 0.65),
                streamingWord(" ready", start: 0.65, end: 0.9)
            ]))
        ]
        let service = rig.makeService(
            factory: FakeWhisperKitClientFactory(
                downloadResult: modelFolder,
                client: client,
                previewClient: previewClient
            ),
            previewInterval: .milliseconds(1),
            previewMinimumSampleDelta: 1
        )

        try await service.prepareModel { _ in }
        try await service.startRecording(reportPreview: { _ in })
        client.emitRecordingAudio(Array(repeating: Float(0.1), count: 10_000))
        await yieldUntil(maxYields: 2_000) { previewClient.streamingTranscribeCallCount == 1 }

        let result = try await service.stopRecording(saveDebugCapture: false)

        #expect(result == "The preview is ready")
        #expect(previewClient.streamingTranscribeCallCount == 1)
        #expect(previewClient.streamingStartingAtSeconds == [0])
        #expect(client.transcribeCallCount == 0)
    }

    @Test func previewSilenceDoesNotAdvanceCoverageAndStopRechecksWithoutHallucinatingTail() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        let previewClient = FakeWhisperKitClient()
        client.voiceActivityResults = [true, false, false]
        previewClient.streamingOutcomes = [
            .success(streamingHypothesis("keep this transcript", start: 0, end: 1))
        ]
        let service = rig.makeService(
            factory: FakeWhisperKitClientFactory(
                downloadResult: modelFolder,
                client: client,
                previewClient: previewClient
            ),
            previewInterval: .milliseconds(1),
            previewMinimumSampleDelta: 1
        )
        var previews: [String] = []

        try await service.prepareModel { _ in }
        try await service.startRecording(reportPreview: { update in
            if case .text(let text) = update {
                previews.append(text)
            }
        })
        client.emitRecordingAudio(Array(repeating: Float(0.2), count: 10_000))
        await yieldUntil(maxYields: 2_000) {
            previews == ["keep this transcript"]
        }
        client.emitRecordingAudio(Array(repeating: Float(0), count: 10_000))
        await yieldUntil(maxYields: 2_000) { client.voiceActivityCallCount == 2 }

        let result = try await service.stopRecording(saveDebugCapture: false)

        #expect(previews == ["keep this transcript"])
        #expect(result == "keep this transcript")
        #expect(client.voiceActivitySampleCounts == [10_000, 10_000, 10_000])
        #expect(previewClient.streamingTranscribeCallCount == 1)
        #expect(client.transcribeCallCount == 0)
    }

    @Test func recordingPreviewImmediatelyUsesAudioCapturedDuringPriorInference() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        let previewClient = FakeWhisperKitClient()
        client.recordingAudioEmittedDuringStart = [0.1]
        previewClient.streamingOutcomes = [
            .success(streamingHypothesis("first", start: 0, end: 1)),
            .success(streamingHypothesis("first second", start: 0, end: 2))
        ]
        previewClient.suspendsStreamingTranscription = true
        let service = rig.makeService(
            factory: FakeWhisperKitClientFactory(
                downloadResult: modelFolder,
                client: client,
                previewClient: previewClient
            ),
            previewInterval: .milliseconds(1),
            previewMinimumSampleDelta: 1
        )

        try await service.prepareModel { _ in }
        try await service.startRecording(reportPreview: { _ in })
        await yieldUntil(maxYields: 2_000) { previewClient.streamingTranscribeCallCount == 1 }

        client.emitRecordingAudio([0.2])
        previewClient.suspendsStreamingTranscription = false
        previewClient.resumeStreamingTranscription()
        await yieldUntil(maxYields: 2_000) { previewClient.streamingTranscribeCallCount == 2 }

        #expect(previewClient.streamingTranscribeCallCount == 2)
        _ = try await service.stopRecording(saveDebugCapture: false)
    }

    @Test func stopRecordingFinalizesOnlyTheSuffixFromTheConfirmedBoundary() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        let previewClient = FakeWhisperKitClient()
        client.audioSamples = Array(repeating: Float(0.2), count: 20_000)
        client.voiceActivityResults = [true, true]
        previewClient.streamingOutcomes = [
            .success(streamingHypothesis(segments: [
                streamingSegment("Alpha ", start: 0, end: 1),
                streamingSegment("beta ", start: 1, end: 2),
                streamingSegment("gamma", start: 2, end: 3)
            ])),
            .success(streamingHypothesis(segments: [
                streamingSegment("beta revised ", start: 1, end: 2.5),
                streamingSegment("gamma delta", start: 2.5, end: 4)
            ]))
        ]
        let service = rig.makeService(
            factory: FakeWhisperKitClientFactory(
                downloadResult: modelFolder,
                client: client,
                previewClient: previewClient
            ),
            previewInterval: .milliseconds(1),
            previewMinimumSampleDelta: 1
        )

        try await service.prepareModel { _ in }
        try await service.startRecording(reportPreview: { _ in })
        client.emitRecordingAudio(Array(repeating: Float(0.2), count: 10_000))
        await yieldUntil(maxYields: 2_000) { previewClient.streamingTranscribeCallCount == 1 }
        let result = try await service.stopRecording(saveDebugCapture: false)

        #expect(result == "Alpha beta revised gamma delta")
        #expect(previewClient.streamingTranscribeCallCount == 2)
        #expect(previewClient.streamingStartingAtSeconds == [0, 1])
        #expect(previewClient.streamingTranscribeSampleCounts == [10_000, 20_000])
        #expect(client.transcribeCallCount == 0)
    }

    @Test func recordingPreviewReportsWhenItsSeparateClientCannotLoad() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        let factory = FakeWhisperKitClientFactory(downloadResult: modelFolder, client: client)
        factory.previewMakeClientError = NSError(
            domain: "CueTests",
            code: 9,
            userInfo: [NSLocalizedDescriptionKey: "preview decoder unavailable"]
        )
        let service = rig.makeService(factory: factory)
        var updates: [TranscriptionPreviewUpdate] = []

        try await service.prepareModel { _ in }
        try await service.startRecording(reportPreview: { updates.append($0) })
        await yieldUntil { updates.contains(.unavailable) }
        _ = try await service.stopRecording(saveDebugCapture: false)

        #expect(updates.contains(.unavailable))
    }

    @Test func stopRecordingRetainsInFlightStreamingClientIfPillIsDisabledDuringRelease() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        let previewClient = FakeWhisperKitClient()
        previewClient.streamingOutcomes = [
            .success(streamingHypothesis("completed while stopping", start: 0, end: 0.6)),
            .success(streamingHypothesis("unwanted whole-recording retry", start: 0, end: 1.2))
        ]
        previewClient.suspendsStreamingTranscription = true
        let service = rig.makeService(
            factory: FakeWhisperKitClientFactory(
                downloadResult: modelFolder,
                client: client,
                previewClient: previewClient
            ),
            previewInterval: .milliseconds(1),
            previewMinimumSampleDelta: 1
        )
        try await service.prepareModel { _ in }
        try await service.startRecording(reportPreview: { _ in })
        client.emitRecordingAudio(Array(repeating: Float(0.2), count: 10_000))
        await yieldUntil { previewClient.streamingTranscribeCallCount == 1 }

        let stopTask = Task {
            try await service.stopRecording(saveDebugCapture: false)
        }
        await yieldUntil(maxYields: 2_000) { client.stopRecordingCallCount == 1 }

        await service.disableRecordingPreview()
        previewClient.suspendsStreamingTranscription = false
        previewClient.resumeStreamingTranscription()

        #expect(try await stopTask.value == "completed while stopping")
        #expect(previewClient.streamingTranscribeCallCount == 1)
        #expect(previewClient.streamingCancellationCount == 0)
        #expect(previewClient.streamingStartingAtSeconds == [0])
        #expect(client.transcribeCallCount == 0)
    }

    @Test func stopRecordingCancelsStaleInFlightInferenceAndFinalizesFromWordBoundary() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        let previewClient = FakeWhisperKitClient()
        client.audioSamples = Array(repeating: Float(0.2), count: 30_000)
        previewClient.streamingOutcomes = [
            .success(streamingWordHypothesis([
                streamingWord("I", start: 0, end: 0.3),
                streamingWord(" sent", start: 0.3, end: 0.6),
                streamingWord(" the", start: 0.6, end: 0.9),
                streamingWord(" draft", start: 0.9, end: 1.2),
                streamingWord(" today", start: 1.2, end: 1.5)
            ])),
            .success(streamingWordHypothesis([
                streamingWord("I", start: 0, end: 0.3),
                streamingWord(" sent", start: 0.3, end: 0.6),
                streamingWord(" the", start: 0.6, end: 0.9),
                streamingWord(" draft", start: 0.9, end: 1.2),
                streamingWord(" to", start: 1.2, end: 1.4),
                streamingWord(" Maya", start: 1.4, end: 1.7)
            ])),
            .success(streamingWordHypothesis([
                streamingWord(" the", start: 0.6, end: 0.9),
                streamingWord(" draft", start: 0.9, end: 1.2),
                streamingWord(" to", start: 1.2, end: 1.4),
                streamingWord(" Maya", start: 1.4, end: 1.7)
            ])),
            .success(streamingWordHypothesis([
                streamingWord(" the", start: 0.6, end: 0.9),
                streamingWord(" draft", start: 0.9, end: 1.2),
                streamingWord(" to", start: 1.2, end: 1.4),
                streamingWord(" Maya", start: 1.4, end: 1.7),
                streamingWord(" now", start: 1.7, end: 1.9)
            ]))
        ]
        let service = rig.makeService(
            factory: FakeWhisperKitClientFactory(
                downloadResult: modelFolder,
                client: client,
                previewClient: previewClient
            ),
            previewInterval: .milliseconds(1),
            previewMinimumSampleDelta: 1
        )
        var previews: [String] = []

        try await service.prepareModel { _ in }
        try await service.startRecording(reportPreview: { update in
            if case .text(let text) = update {
                previews.append(text)
            }
        })
        client.emitRecordingAudio(Array(repeating: Float(0.1), count: 10_000))
        await yieldUntil(maxYields: 2_000) {
            previews == ["I sent the draft today"]
        }
        client.emitRecordingAudio(Array(repeating: Float(0.2), count: 10_000))
        await yieldUntil(maxYields: 2_000) {
            previews == ["I sent the draft today", "I sent the draft to Maya"]
        }

        previewClient.suspendsStreamingTranscription = true
        client.emitRecordingAudio(Array(repeating: Float(0.3), count: 5_000))
        await yieldUntil(maxYields: 2_000) { previewClient.streamingTranscribeCallCount == 3 }
        client.emitRecordingAudio(Array(repeating: Float(0.4), count: 5_000))

        let stopTask = Task {
            try await service.stopRecording(saveDebugCapture: false)
        }
        await yieldUntil(maxYields: 2_000) {
            client.stopRecordingCallCount == 1 && client.voiceActivityCallCount >= 4
        }

        previewClient.suspendsStreamingTranscription = false
        previewClient.resumeStreamingTranscription()
        let result = try await stopTask.value

        #expect(result == "I sent the draft to Maya now")
        #expect(previewClient.streamingCancellationCount == 1)
        #expect(previewClient.streamingTranscribeCallCount == 4)
        #expect(previewClient.streamingStartingAtSeconds == [0, 0, 0.6, 0.6])
        #expect(client.transcribeCallCount == 0)
    }

    @Test func smallVoicedTailPreservesLatestCumulativeTranscriptWithoutWholeRetry() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        let previewClient = FakeWhisperKitClient()
        client.audioSamples = Array(repeating: Float(0.2), count: 24_000)
        previewClient.streamingOutcomes = [
            .success(streamingWordHypothesis([
                streamingWord("Keep", start: 0, end: 0.35),
                streamingWord(" this", start: 0.35, end: 0.65),
                streamingWord(" transcript", start: 0.65, end: 1)
            ])),
            .success(WhisperKitStreamingHypothesis(text: "", segments: [], words: []))
        ]
        let service = rig.makeService(
            factory: FakeWhisperKitClientFactory(
                downloadResult: modelFolder,
                client: client,
                previewClient: previewClient
            ),
            previewInterval: .milliseconds(1),
            previewMinimumSampleDelta: 1
        )
        var previews: [String] = []

        try await service.prepareModel { _ in }
        try await service.startRecording(reportPreview: { update in
            if case .text(let text) = update {
                previews.append(text)
            }
        })
        client.emitRecordingAudio(Array(repeating: Float(0.2), count: 16_000))
        await yieldUntil(maxYields: 2_000) {
            previews == ["Keep this transcript"]
        }
        let result = try await service.stopRecording(saveDebugCapture: false)

        #expect(result == "Keep this transcript")
        #expect(previewClient.streamingTranscribeCallCount == 1)
        #expect(previewClient.streamingStartingAtSeconds == [0])
        #expect(client.voiceActivitySampleCounts.last == 8_000)
        #expect(client.transcribeCallCount == 0)
    }

    @Test func voiceActivityReceivesExactImmutableNewAndUncoveredAudioSlices() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        let previewClient = FakeWhisperKitClient()
        let firstChunk = Array(repeating: Float(0.1), count: 2_000)
        let secondChunk = Array(repeating: Float(0.2), count: 3_000)
        let uncoveredTail = Array(repeating: Float(0.3), count: 4_000)
        client.audioSamples = firstChunk + secondChunk + uncoveredTail
        previewClient.streamingOutcomes = [
            .success(streamingWordHypothesis([
                streamingWord("one", start: 0, end: 0.1),
                streamingWord(" two", start: 0.1, end: 0.2),
                streamingWord(" three", start: 0.2, end: 0.3),
                streamingWord(" old", start: 0.3, end: 0.4)
            ])),
            .success(streamingWordHypothesis([
                streamingWord("one", start: 0, end: 0.1),
                streamingWord(" two", start: 0.1, end: 0.2),
                streamingWord(" three", start: 0.2, end: 0.3),
                streamingWord(" four", start: 0.3, end: 0.4)
            ])),
            .success(streamingWordHypothesis([
                streamingWord(" two", start: 0.1, end: 0.2),
                streamingWord(" three", start: 0.2, end: 0.3),
                streamingWord(" four", start: 0.3, end: 0.4),
                streamingWord(" five", start: 0.4, end: 0.5)
            ]))
        ]
        let service = rig.makeService(
            factory: FakeWhisperKitClientFactory(
                downloadResult: modelFolder,
                client: client,
                previewClient: previewClient
            ),
            previewInterval: .milliseconds(1),
            previewMinimumSampleDelta: 1
        )
        var previews: [String] = []

        try await service.prepareModel { _ in }
        try await service.startRecording(reportPreview: { update in
            if case .text(let text) = update {
                previews.append(text)
            }
        })
        client.emitRecordingAudio(firstChunk)
        await yieldUntil(maxYields: 2_000) { previews == ["one two three old"] }
        client.emitRecordingAudio(secondChunk)
        await yieldUntil(maxYields: 2_000) {
            previews == ["one two three old", "one two three four"]
        }
        let result = try await service.stopRecording(saveDebugCapture: false)

        #expect(result == "one two three four five")
        #expect(client.voiceActivitySamples == [firstChunk, secondChunk, uncoveredTail])
        #expect(previewClient.streamingTranscribeCallCount == 3)
        #expect(client.transcribeCallCount == 0)
    }

    @Test func stopRecordingKeepsLatestCumulativeTextWhenTailRefinementFails() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        let previewClient = FakeWhisperKitClient()
        client.audioSamples = Array(repeating: Float(0.2), count: 30_000)
        client.transcriptions = [
            WhisperKitTranscriptionSegment(
                text: "whole clip fallback",
                language: "en",
                modelLoadDuration: 0.2,
                pipelineDuration: 0.4
            )
        ]
        previewClient.streamingOutcomes = [
            .success(streamingWordHypothesis([
                streamingWord("I", start: 0, end: 0.3),
                streamingWord(" sent", start: 0.3, end: 0.6),
                streamingWord(" the", start: 0.6, end: 0.9),
                streamingWord(" draft", start: 0.9, end: 1.2),
                streamingWord(" today", start: 1.2, end: 1.5)
            ])),
            .success(streamingWordHypothesis([
                streamingWord("I", start: 0, end: 0.3),
                streamingWord(" sent", start: 0.3, end: 0.6),
                streamingWord(" the", start: 0.6, end: 0.9),
                streamingWord(" draft", start: 0.9, end: 1.2),
                streamingWord(" to", start: 1.2, end: 1.4),
                streamingWord(" Maya", start: 1.4, end: 1.7)
            ])),
            .failure(NSError(
                domain: "CueTests",
                code: 42,
                userInfo: [NSLocalizedDescriptionKey: "tail decoder failed"]
            ))
        ]
        let service = rig.makeService(
            factory: FakeWhisperKitClientFactory(
                downloadResult: modelFolder,
                client: client,
                previewClient: previewClient
            ),
            previewInterval: .milliseconds(1),
            previewMinimumSampleDelta: 1
        )

        try await service.prepareModel { _ in }
        try await service.startRecording(reportPreview: { _ in })
        client.emitRecordingAudio(Array(repeating: Float(0.2), count: 10_000))
        await yieldUntil(maxYields: 2_000) { previewClient.streamingTranscribeCallCount == 1 }
        client.emitRecordingAudio(Array(repeating: Float(0.3), count: 10_000))
        await yieldUntil(maxYields: 2_000) { previewClient.streamingTranscribeCallCount == 2 }
        let result = try await service.stopRecording(saveDebugCapture: false)

        #expect(result == "I sent the draft to Maya")
        #expect(previewClient.streamingTranscribeCallCount == 3)
        #expect(previewClient.streamingStartingAtSeconds == [0, 0, 0.6])
        #expect(client.transcribeCallCount == 0)
    }

    @Test func stopRecordingRejectsWhitespaceOnlyTranscript() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        client.transcriptions = [
            WhisperKitTranscriptionSegment(text: "   ", language: "en", modelLoadDuration: 0.1, pipelineDuration: 0.2)
        ]
        let factory = FakeWhisperKitClientFactory(downloadResult: modelFolder, client: client)
        let service = rig.makeService(factory: factory)

        try await service.prepareModel { _ in }
        try await service.startRecording()

        await #expect(throws: CueError.emptyTranscript) {
            try await service.stopRecording(saveDebugCapture: false)
        }
    }

    @Test func stopRecordingRejectsBlankAudioSentinelTranscript() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        client.transcriptions = [
            WhisperKitTranscriptionSegment(text: "[BLANK_AUDIO]", language: "en", modelLoadDuration: 0.1, pipelineDuration: 0.2)
        ]
        let factory = FakeWhisperKitClientFactory(downloadResult: modelFolder, client: client)
        let service = rig.makeService(factory: factory)

        try await service.prepareModel { _ in }
        try await service.startRecording()

        await #expect(throws: CueError.emptyTranscript) {
            try await service.stopRecording(saveDebugCapture: false)
        }
    }

    @Test func startRecordingRejectsASecondConcurrentRecording() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let factory = FakeWhisperKitClientFactory(downloadResult: modelFolder)
        let service = rig.makeService(factory: factory)

        try await service.prepareModel { _ in }
        try await service.startRecording()

        await #expect(throws: CueError.recordingAlreadyInProgress) {
            try await service.startRecording()
        }
    }

    @Test func stopRecordingRejectsClipsShorterThanMinimumDuration() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        client.audioSamples = Array(repeating: Float(0), count: 1_000)
        let factory = FakeWhisperKitClientFactory(downloadResult: modelFolder, client: client)
        let service = rig.makeService(factory: factory)

        try await service.prepareModel { _ in }
        try await service.startRecording()

        do {
            _ = try await service.stopRecording(saveDebugCapture: false)
            #expect(Bool(false), "Expected recordingTooShort error")
        } catch let error as CueError {
            guard case .recordingTooShort(let actual, let minimum) = error else {
                #expect(Bool(false), "Expected recordingTooShort but got \(error)")
                return
            }

            #expect(actual < minimum)
            #expect(minimum == CueAppConfiguration.minimumRecordingDuration)
        }
    }

    @Test func stopRecordingMapsUnexpectedTranscriptionErrors() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        client.transcribeError = NSError(
            domain: "CueTests",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "decoder offline"]
        )
        let factory = FakeWhisperKitClientFactory(downloadResult: modelFolder, client: client)
        let service = rig.makeService(factory: factory)

        try await service.prepareModel { _ in }
        try await service.startRecording()

        await #expect(throws: CueError.transcriptionFailed("decoder offline")) {
            try await service.stopRecording(saveDebugCapture: false)
        }
    }

    @Test func debugCaptureStoreUsesInjectedDateUUIDAndTimeZoneForCapturePath() async throws {
        let rig = WhisperKitServiceTestRig()

        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let fixedDate = try #require(DateComponents(
            calendar: Calendar(identifier: .iso8601),
            timeZone: timeZone,
            year: 2026,
            month: 5,
            day: 4,
            hour: 12,
            minute: 34,
            second: 56,
            nanosecond: 789_000_000
        ).date)
        let fixedUUID = try #require(UUID(uuidString: "12345678-1234-5678-1234-567812345678"))
        let store = DebugCaptureStore(
            rootDirectory: rig.debugCaptureDirectory,
            dateProvider: { fixedDate },
            uuidProvider: { fixedUUID },
            timeZone: timeZone
        )

        let capture = try store.createCapture(audioSamples: [0])

        let expectedCaptureID = "2026-05-04T12-34-56.789Z-12345678-1234-5678-1234-567812345678"
        #expect(capture.lastPathComponent == expectedCaptureID)
        #expect(capture.deletingLastPathComponent().lastPathComponent == "2026-05-04")
        #expect(FileManager.default.fileExists(atPath: capture.appendingPathComponent("clip.wav").path))
    }

    @Test func debugCaptureStoreWritesTypedResultJSON() async throws {
        let rig = WhisperKitServiceTestRig()

        let store = DebugCaptureStore(rootDirectory: rig.debugCaptureDirectory)
        let capture = try store.createCapture(audioSamples: [0])

        try store.saveResult(
            for: capture,
            sampleCount: 1,
            recordingDuration: 1.5,
            segments: [
                WhisperKitTranscriptionSegment(
                    text: "hello",
                    language: "en",
                    modelLoadDuration: 0.25,
                    pipelineDuration: 0.5
                )
            ],
            finalTranscript: "hello",
            errorMessage: nil
        )

        let resultData = try Data(contentsOf: capture.appendingPathComponent("result.json"))
        let document = try JSONDecoder().decode(DebugCaptureResultDocument.self, from: resultData)

        #expect(document.captureID == capture.lastPathComponent)
        #expect(document.sampleCount == 1)
        #expect(document.recordingDuration == 1.5)
        #expect(document.finalTranscript == "hello")
        #expect(document.errorMessage == nil)
        #expect(document.rawSegments == [
            WhisperKitTranscriptionSegment(
                text: "hello",
                language: "en",
                modelLoadDuration: 0.25,
                pipelineDuration: 0.5
            )
        ])
    }

    @Test func debugCaptureStoreUsesInjectedSampleRateInWAVHeader() async throws {
        let rig = WhisperKitServiceTestRig()

        let store = DebugCaptureStore(rootDirectory: rig.debugCaptureDirectory, sampleRate: 22_050)

        let capture = try store.createCapture(audioSamples: [0, 0.5])
        let wavData = try Data(contentsOf: capture.appendingPathComponent("clip.wav"))

        #expect(littleEndianUInt32(in: wavData, at: 24) == 22_050)
        #expect(littleEndianUInt32(in: wavData, at: 28) == 44_100)
    }

    @Test func stopRecordingSavesDebugCaptureArtifactsWhenEnabled() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        client.audioSamples = Array(repeating: Float(0.25), count: 32_000)
        client.transcriptions = [
            WhisperKitTranscriptionSegment(text: "hello world", language: "en", modelLoadDuration: 0.2, pipelineDuration: 0.4)
        ]

        let service = rig.makeService(
            factory: FakeWhisperKitClientFactory(downloadResult: modelFolder, client: client)
        )

        try await service.prepareModel { _ in }
        try await service.startRecording()
        let result = try await service.stopRecording(saveDebugCapture: true)

        #expect(result == "hello world")

        let captureFolders = try FileManager.default.contentsOfDirectory(
            at: rig.debugCaptureDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        #expect(captureFolders.count == 1)

        let dayFolder = captureFolders[0]
        let captures = try FileManager.default.contentsOfDirectory(
            at: dayFolder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        #expect(captures.count == 1)

        let captureFolder = captures[0]
        let wavURL = captureFolder.appendingPathComponent("clip.wav")
        let resultURL = captureFolder.appendingPathComponent("result.json")

        #expect(FileManager.default.fileExists(atPath: wavURL.path))
        #expect(FileManager.default.fileExists(atPath: resultURL.path))

        let resultData = try Data(contentsOf: resultURL)
        let document = try JSONDecoder().decode(DebugCaptureResultDocument.self, from: resultData)

        #expect(document.sampleCount == 32_000)
        #expect(document.finalTranscript == "hello world")
        #expect(document.errorMessage == nil)
        #expect(document.rawSegments.map(\.text) == ["hello world"])
    }

    @Test func stopRecordingSavesDebugCaptureErrorArtifactsWhenTranscriptionFails() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        client.audioSamples = Array(repeating: Float(0.25), count: 32_000)
        client.transcribeError = NSError(
            domain: "CueTests",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "decoder offline"]
        )

        let service = rig.makeService(
            factory: FakeWhisperKitClientFactory(downloadResult: modelFolder, client: client)
        )

        try await service.prepareModel { _ in }
        try await service.startRecording()

        await #expect(throws: CueError.transcriptionFailed("decoder offline")) {
            try await service.stopRecording(saveDebugCapture: true)
        }

        let dayFolder = try #require(try firstDirectory(at: rig.debugCaptureDirectory))
        let captureFolder = try #require(try firstDirectory(at: dayFolder))
        let resultData = try Data(contentsOf: captureFolder.appendingPathComponent("result.json"))
        let document = try JSONDecoder().decode(DebugCaptureResultDocument.self, from: resultData)

        #expect(document.finalTranscript.isEmpty)
        #expect(document.errorMessage == "decoder offline")
        #expect(document.rawSegments.isEmpty)
    }

    @Test func stopRecordingIgnoresDebugCaptureWriteFailures() async throws {
        let rig = WhisperKitServiceTestRig()
        let modelFolder = rig.downloadedModelFolder()
        let client = FakeWhisperKitClient()
        client.audioSamples = Array(repeating: Float(0.25), count: 32_000)

        let service = WhisperKitTranscriptionService(
            defaults: rig.defaults,
            modelDirectory: rig.modelDirectory,
            clientFactory: FakeWhisperKitClientFactory(downloadResult: modelFolder, client: client),
            debugCaptureStore: FailingDebugCaptureStore()
        )

        try await service.prepareModel { _ in }
        try await service.startRecording()
        let result = try await service.stopRecording(saveDebugCapture: true)

        #expect(result == "hello")
    }
}

private final class WhisperKitServiceTestRig {
    let rootDirectory: URL
    let modelDirectory: URL
    let debugCaptureDirectory: URL
    let defaults: UserDefaults

    private let defaultsSuiteName: String

    init() {
        let identifier = UUID().uuidString
        defaultsSuiteName = "CueWhisperTests.\(identifier)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(defaultsSuiteName, isDirectory: true)
        modelDirectory = rootDirectory.appendingPathComponent("Models", isDirectory: true)
        debugCaptureDirectory = rootDirectory.appendingPathComponent("DebugCaptures", isDirectory: true)
    }

    func downloadedModelFolder() -> URL {
        rootDirectory.appendingPathComponent(
            CueAppConfiguration.expectedDownloadedModelFolderName(for: CueAppConfiguration.modelID),
            isDirectory: true
        )
    }

    func makeService(
        factory: any WhisperKitClientFactory,
        debugCaptureStore: (any DebugCaptureStoring)? = nil,
        previewInterval: Duration = .milliseconds(100),
        previewMinimumSampleDelta: Int = 16_000
    ) -> WhisperKitTranscriptionService {
        WhisperKitTranscriptionService(
            defaults: defaults,
            modelDirectory: modelDirectory,
            clientFactory: factory,
            debugCaptureStore: debugCaptureStore ?? DebugCaptureStore(rootDirectory: debugCaptureDirectory),
            previewInterval: previewInterval,
            previewMinimumSampleDelta: previewMinimumSampleDelta
        )
    }

    deinit {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: rootDirectory)
    }
}

private final class FakeWhisperKitClientFactory: WhisperKitClientFactory {
    var downloadCallCount = 0
    var makeClientCallCount = 0
    var downloadedVariants: [String] = []
    var makeClientModelIDs: [String] = []
    var downloadResult: URL
    var makeClientError: Error?
    var previewMakeClientError: Error?
    var client: FakeWhisperKitClient
    var previewClient: FakeWhisperKitClient?
    var progressToReportDuringDownload: Double? = 0.5
    var capturedProgressHandler: ((Double) -> Void)?
    var suspendsPreviewClientCreation = false
    private var previewClientCreationContinuation: CheckedContinuation<Void, Never>?

    init(
        downloadResult: URL,
        client: FakeWhisperKitClient = FakeWhisperKitClient(),
        previewClient: FakeWhisperKitClient? = nil
    ) {
        self.downloadResult = downloadResult
        self.client = client
        self.previewClient = previewClient
    }

    func downloadModel(
        variant: String,
        downloadBase: URL,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {
        _ = downloadBase
        downloadCallCount += 1
        downloadedVariants.append(variant)
        capturedProgressHandler = onProgress

        if let progressToReportDuringDownload {
            onProgress(progressToReportDuringDownload)
        }

        return downloadResult
    }

    func makeClient(
        modelID: String,
        modelDirectory: URL,
        modelFolder: URL
    ) async throws -> any WhisperKitClient {
        _ = modelDirectory
        _ = modelFolder
        let callIndex = makeClientCallCount
        makeClientCallCount += 1
        makeClientModelIDs.append(modelID)

        if callIndex > 0, suspendsPreviewClientCreation {
            await withCheckedContinuation { continuation in
                previewClientCreationContinuation = continuation
            }
        }

        if callIndex > 0, let previewMakeClientError {
            throw previewMakeClientError
        }

        if let makeClientError {
            throw makeClientError
        }

        if callIndex > 0, let previewClient {
            return previewClient
        }

        return client
    }

    func resumePreviewClientCreation() {
        let continuation = previewClientCreationContinuation
        previewClientCreationContinuation = nil
        continuation?.resume()
    }
}

private enum FakeStreamingOutcome {
    case success(WhisperKitStreamingHypothesis)
    case failure(Error)
}

private final class FakeWhisperKitClient: WhisperKitClient {
    private var storedAudioSamples = Array(repeating: Float(0), count: 20_000)
    var audioSamplesReadCallCount = 0
    var audioSamples: [Float] {
        get {
            audioSamplesReadCallCount += 1
            return storedAudioSamples
        }
        set {
            storedAudioSamples = newValue
        }
    }
    var transcriptions: [WhisperKitTranscriptionSegment] = [
        WhisperKitTranscriptionSegment(text: "hello", language: "en", modelLoadDuration: 0.2, pipelineDuration: 0.4)
    ]
    var startRecordingCallCount = 0
    var stopRecordingCallCount = 0
    var voiceActivityCallCount = 0
    var voiceActivitySampleCounts: [Int] = []
    var voiceActivitySamples: [[Float]] = []
    var voiceActivityResults: [Bool] = []
    var defaultVoiceActivityResult = true
    var transcribeCallCount = 0
    var streamingTranscribeCallCount = 0
    var streamingTranscribeSampleCounts: [Int] = []
    var streamingTranscribeSamples: [[Float]] = []
    var streamingStartingAtSeconds: [Float] = []
    var streamingCancellationCount = 0
    var streamingOutcomes: [FakeStreamingOutcome] = []
    var transcribeError: Error?
    var suspendsStreamingTranscription = false
    var recordingAudioEmittedDuringStart: [Float]?
    private var recordingAudioHandler: RecordingAudioBufferHandler?
    private var streamingTranscriptionContinuation: CheckedContinuation<Void, Never>?

    func startRecording(onAudioBuffer: RecordingAudioBufferHandler?) throws {
        startRecordingCallCount += 1
        recordingAudioHandler = onAudioBuffer
        if let recordingAudioEmittedDuringStart {
            onAudioBuffer?(recordingAudioEmittedDuringStart)
        }
    }

    func stopRecording() {
        stopRecordingCallCount += 1
    }

    func hasVoiceActivity(in audioSamples: [Float]) -> Bool {
        let callIndex = voiceActivityCallCount
        voiceActivityCallCount += 1
        voiceActivitySampleCounts.append(audioSamples.count)
        voiceActivitySamples.append(audioSamples)

        guard callIndex < voiceActivityResults.count else {
            return defaultVoiceActivityResult
        }
        return voiceActivityResults[callIndex]
    }

    func transcribe(audioSamples: [Float]) async throws -> [WhisperKitTranscriptionSegment] {
        _ = audioSamples
        transcribeCallCount += 1

        if let transcribeError {
            throw transcribeError
        }

        return transcriptions
    }

    func transcribeStreaming(
        audioSamples: [Float],
        startingAt seconds: Float
    ) async throws -> WhisperKitStreamingHypothesis {
        let callIndex = streamingTranscribeCallCount
        streamingTranscribeCallCount += 1
        streamingTranscribeSampleCounts.append(audioSamples.count)
        streamingTranscribeSamples.append(audioSamples)
        streamingStartingAtSeconds.append(seconds)

        if suspendsStreamingTranscription {
            await withCheckedContinuation { continuation in
                streamingTranscriptionContinuation = continuation
            }
        }

        if Task.isCancelled {
            streamingCancellationCount += 1
            throw CancellationError()
        }

        if callIndex < streamingOutcomes.count {
            switch streamingOutcomes[callIndex] {
            case .success(let hypothesis):
                return hypothesis
            case .failure(let error):
                throw error
            }
        }

        return WhisperKitStreamingHypothesis(
            text: transcriptions.map(\.text).joined(),
            segments: transcriptions
        )
    }

    func emitRecordingAudio(_ samples: [Float]) {
        recordingAudioHandler?(samples)
    }

    func resumeStreamingTranscription() {
        let continuation = streamingTranscriptionContinuation
        streamingTranscriptionContinuation = nil
        continuation?.resume()
    }
}

private final class FailingDebugCaptureStore: DebugCaptureStoring {
    func createCapture(audioSamples: [Float]) throws -> URL {
        _ = audioSamples
        throw NSError(domain: "CueTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "disk full"])
    }

    func saveResult(
        for capture: URL,
        sampleCount: Int,
        recordingDuration: TimeInterval,
        segments: [WhisperKitTranscriptionSegment],
        finalTranscript: String,
        errorMessage: String?
    ) throws {
        _ = capture
        _ = sampleCount
        _ = recordingDuration
        _ = segments
        _ = finalTranscript
        _ = errorMessage
        throw NSError(domain: "CueTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "disk full"])
    }
}

private func streamingHypothesis(
    _ text: String,
    start: Float = 0,
    end: Float = 1
) -> WhisperKitStreamingHypothesis {
    streamingHypothesis(segments: [
        streamingSegment(text, start: start, end: end)
    ])
}

private func streamingHypothesis(
    segments: [WhisperKitTranscriptionSegment]
) -> WhisperKitStreamingHypothesis {
    WhisperKitStreamingHypothesis(
        text: segments.map(\.text).joined(),
        segments: segments
    )
}

private func streamingWordHypothesis(
    _ words: [WhisperKitWordTiming]
) -> WhisperKitStreamingHypothesis {
    let text = words.map(\.text).joined()
    let segment = streamingSegment(
        text,
        start: words.first?.start ?? 0,
        end: words.last?.end ?? 0
    )
    return WhisperKitStreamingHypothesis(
        text: text,
        segments: words.isEmpty ? [] : [segment],
        words: words
    )
}

private func streamingWord(
    _ text: String,
    start: Float,
    end: Float
) -> WhisperKitWordTiming {
    WhisperKitWordTiming(text: text, start: start, end: end)
}

private func streamingSegment(
    _ text: String,
    start: Float,
    end: Float
) -> WhisperKitTranscriptionSegment {
    WhisperKitTranscriptionSegment(
        text: text,
        language: "en",
        modelLoadDuration: 0.1,
        pipelineDuration: 0.2,
        start: start,
        end: end
    )
}

private func firstDirectory(at url: URL) throws -> URL? {
    let entries = try FileManager.default.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    )
    return entries.first
}

private func littleEndianUInt32(in data: Data, at offset: Int) -> UInt32 {
    precondition(offset + 4 <= data.count)

    var value: UInt32 = 0
    for byteOffset in 0..<4 {
        value |= UInt32(data[offset + byteOffset]) << UInt32(byteOffset * 8)
    }
    return value
}
