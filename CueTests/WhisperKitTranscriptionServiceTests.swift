import Foundation
import Testing
@testable import Cue

@MainActor
struct WhisperKitTranscriptionServiceTests {
    @Test func prepareModelUsesCachedPathWithoutDownloading() async throws {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let cachedModelFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: cachedModelFolder, withIntermediateDirectories: true)
        defaults.set(cachedModelFolder.path, forKey: CueAppConfiguration.cachedModelPathDefaultsKey)

        let factory = FakeWhisperKitClientFactory(downloadResult: cachedModelFolder)
        let service = WhisperKitTranscriptionService(defaults: defaults, clientFactory: factory)
        var statuses: [ModelPreparationStatus] = []
        service.statusHandler = { statuses.append($0) }

        try await service.prepareModel()

        #expect(factory.downloadCallCount == 0)
        #expect(factory.makeClientCallCount == 1)
        #expect(statuses == [.checkingCache, .loading, .ready])
    }

    @Test func prepareModelReportsLoadFailuresSeparatelyFromDownloadFailures() async throws {
        let modelFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let factory = FakeWhisperKitClientFactory(downloadResult: modelFolder)
        factory.makeClientError = NSError(domain: "CueTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "bad weights"])
        let service = WhisperKitTranscriptionService(clientFactory: factory)

        await #expect(throws: CueError.modelLoadFailed("bad weights")) {
            try await service.prepareModel()
        }
    }

    @Test func stopRecordingBuildsResultFromClientSegments() async throws {
        let modelFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = FakeWhisperKitClient()
        client.transcriptions = [
            WhisperKitTranscriptionSegment(text: "hello ", language: "en", modelLoadDuration: 0.2, pipelineDuration: 0.4),
            WhisperKitTranscriptionSegment(text: "world", language: "en", modelLoadDuration: 0.4, pipelineDuration: 0.6)
        ]
        let factory = FakeWhisperKitClientFactory(downloadResult: modelFolder, client: client)
        let service = WhisperKitTranscriptionService(clientFactory: factory)

        try await service.startRecording()
        let result = try await service.stopRecording()

        #expect(client.startRecordingCallCount == 1)
        #expect(client.stopRecordingCallCount == 1)
        #expect(result.text == "hello world")
        #expect(result.language == "en")
        #expect(result.modelLoadDuration == 0.4)
        #expect(result.pipelineDuration == 1.0)
    }

    @Test func stopRecordingRejectsWhitespaceOnlyTranscript() async throws {
        let modelFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = FakeWhisperKitClient()
        client.transcriptions = [
            WhisperKitTranscriptionSegment(text: "   ", language: "en", modelLoadDuration: 0.1, pipelineDuration: 0.2)
        ]
        let factory = FakeWhisperKitClientFactory(downloadResult: modelFolder, client: client)
        let service = WhisperKitTranscriptionService(clientFactory: factory)

        try await service.startRecording()

        await #expect(throws: CueError.emptyTranscript) {
            try await service.stopRecording()
        }
    }

    @Test func stopRecordingRejectsBlankAudioSentinelTranscript() async throws {
        let modelFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = FakeWhisperKitClient()
        client.transcriptions = [
            WhisperKitTranscriptionSegment(text: "[BLANK_AUDIO]", language: "en", modelLoadDuration: 0.1, pipelineDuration: 0.2)
        ]
        let factory = FakeWhisperKitClientFactory(downloadResult: modelFolder, client: client)
        let service = WhisperKitTranscriptionService(clientFactory: factory)

        try await service.startRecording()

        await #expect(throws: CueError.emptyTranscript) {
            try await service.stopRecording()
        }
    }

    @Test func startRecordingRejectsASecondConcurrentRecording() async throws {
        let modelFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let factory = FakeWhisperKitClientFactory(downloadResult: modelFolder)
        let service = WhisperKitTranscriptionService(clientFactory: factory)

        try await service.startRecording()

        await #expect(throws: CueError.recordingAlreadyInProgress) {
            try await service.startRecording()
        }
    }

    @Test func stopRecordingRejectsClipsShorterThanMinimumDuration() async throws {
        let modelFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = FakeWhisperKitClient()
        client.audioSamples = Array(repeating: Float(0), count: 1_000)
        let factory = FakeWhisperKitClientFactory(downloadResult: modelFolder, client: client)
        let service = WhisperKitTranscriptionService(clientFactory: factory)

        try await service.startRecording()

        do {
            _ = try await service.stopRecording()
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
        let modelFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = FakeWhisperKitClient()
        client.transcribeError = NSError(
            domain: "CueTests",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "decoder offline"]
        )
        let factory = FakeWhisperKitClientFactory(downloadResult: modelFolder, client: client)
        let service = WhisperKitTranscriptionService(clientFactory: factory)

        try await service.startRecording()

        await #expect(throws: CueError.transcriptionFailed("decoder offline")) {
            try await service.stopRecording()
        }
    }

    @Test func stopRecordingSavesDebugCaptureArtifactsWhenEnabled() async throws {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: CueAppConfiguration.debugCapturesEnabledDefaultsKey)

        let captureRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let modelFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = FakeWhisperKitClient()
        client.audioSamples = Array(repeating: Float(0.25), count: 32_000)
        client.transcriptions = [
            WhisperKitTranscriptionSegment(text: "hello world", language: "en", modelLoadDuration: 0.2, pipelineDuration: 0.4)
        ]

        let service = WhisperKitTranscriptionService(
            defaults: defaults,
            clientFactory: FakeWhisperKitClientFactory(downloadResult: modelFolder, client: client),
            debugCaptureStore: DebugCaptureStore(rootDirectory: captureRoot)
        )

        try await service.startRecording()
        let result = try await service.stopRecording()

        #expect(result.text == "hello world")

        let captureFolders = try FileManager.default.contentsOfDirectory(
            at: captureRoot,
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
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: CueAppConfiguration.debugCapturesEnabledDefaultsKey)

        let captureRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let modelFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = FakeWhisperKitClient()
        client.audioSamples = Array(repeating: Float(0.25), count: 32_000)
        client.transcribeError = NSError(
            domain: "CueTests",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "decoder offline"]
        )

        let service = WhisperKitTranscriptionService(
            defaults: defaults,
            clientFactory: FakeWhisperKitClientFactory(downloadResult: modelFolder, client: client),
            debugCaptureStore: DebugCaptureStore(rootDirectory: captureRoot)
        )

        try await service.startRecording()

        await #expect(throws: CueError.transcriptionFailed("decoder offline")) {
            try await service.stopRecording()
        }

        let dayFolder = try #require(try firstDirectory(at: captureRoot))
        let captureFolder = try #require(try firstDirectory(at: dayFolder))
        let resultData = try Data(contentsOf: captureFolder.appendingPathComponent("result.json"))
        let document = try JSONDecoder().decode(DebugCaptureResultDocument.self, from: resultData)

        #expect(document.finalTranscript.isEmpty)
        #expect(document.errorMessage == "decoder offline")
        #expect(document.rawSegments.isEmpty)
    }

    @Test func stopRecordingIgnoresDebugCaptureWriteFailures() async throws {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: CueAppConfiguration.debugCapturesEnabledDefaultsKey)

        let modelFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = FakeWhisperKitClient()
        client.audioSamples = Array(repeating: Float(0.25), count: 32_000)

        let service = WhisperKitTranscriptionService(
            defaults: defaults,
            clientFactory: FakeWhisperKitClientFactory(downloadResult: modelFolder, client: client),
            debugCaptureStore: FailingDebugCaptureStore()
        )

        try await service.startRecording()
        let result = try await service.stopRecording()

        #expect(result.text == "hello")
    }
}

private final class FakeWhisperKitClientFactory: WhisperKitClientFactory {
    var downloadCallCount = 0
    var makeClientCallCount = 0
    var downloadResult: URL
    var downloadError: Error?
    var makeClientError: Error?
    var client: FakeWhisperKitClient

    init(downloadResult: URL, client: FakeWhisperKitClient = FakeWhisperKitClient()) {
        self.downloadResult = downloadResult
        self.client = client
    }

    func downloadModel(
        variant: String,
        downloadBase: URL,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {
        _ = variant
        _ = downloadBase
        downloadCallCount += 1
        onProgress(0.5)

        if let downloadError {
            throw downloadError
        }

        return downloadResult
    }

    func makeClient(
        modelID: String,
        modelDirectory: URL,
        modelFolder: URL
    ) async throws -> any WhisperKitClient {
        _ = modelID
        _ = modelDirectory
        _ = modelFolder
        makeClientCallCount += 1

        if let makeClientError {
            throw makeClientError
        }

        return client
    }
}

private final class FakeWhisperKitClient: WhisperKitClient {
    var audioSamples = Array(repeating: Float(0), count: 20_000)
    var transcriptions: [WhisperKitTranscriptionSegment] = [
        WhisperKitTranscriptionSegment(text: "hello", language: "en", modelLoadDuration: 0.2, pipelineDuration: 0.4)
    ]
    var startRecordingCallCount = 0
    var stopRecordingCallCount = 0
    var startRecordingError: Error?
    var transcribeError: Error?

    func startRecording() throws {
        startRecordingCallCount += 1

        if let startRecordingError {
            throw startRecordingError
        }
    }

    func stopRecording() {
        stopRecordingCallCount += 1
    }

    func transcribe(audioSamples: [Float], language: String) async throws -> [WhisperKitTranscriptionSegment] {
        _ = audioSamples
        _ = language

        if let transcribeError {
            throw transcribeError
        }

        return transcriptions
    }
}

private final class FailingDebugCaptureStore: DebugCaptureStoring {
    func createCapture(audioSamples: [Float], recordingDuration: TimeInterval) async throws -> DebugCaptureHandle {
        _ = audioSamples
        _ = recordingDuration
        throw NSError(domain: "CueTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "disk full"])
    }

    func saveResult(
        for capture: DebugCaptureHandle,
        sampleCount: Int,
        recordingDuration: TimeInterval,
        segments: [WhisperKitTranscriptionSegment],
        finalTranscript: String,
        errorMessage: String?
    ) async throws {
        _ = capture
        _ = sampleCount
        _ = recordingDuration
        _ = segments
        _ = finalTranscript
        _ = errorMessage
        throw NSError(domain: "CueTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "disk full"])
    }
}

private func firstDirectory(at url: URL) throws -> URL? {
    let entries = try FileManager.default.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    )
    return entries.first
}
