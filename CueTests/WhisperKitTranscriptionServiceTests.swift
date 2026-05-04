import Foundation
import Testing
@testable import Cue

@MainActor
struct WhisperKitTranscriptionServiceTests {
    @Test func prepareModelUsesCachedPathWithoutDownloading() async throws {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let cachedModelFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent(CueAppConfiguration.expectedDownloadedModelFolderName(for: CueAppConfiguration.modelID))
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

    @Test func prepareModelUsesCurrentHardcodedModelForDownloadAndLoad() async throws {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let modelFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent(CueAppConfiguration.expectedDownloadedModelFolderName(for: CueAppConfiguration.modelID))
        let factory = FakeWhisperKitClientFactory(downloadResult: modelFolder)
        let service = WhisperKitTranscriptionService(defaults: defaults, clientFactory: factory)

        try await service.prepareModel()

        #expect(factory.downloadCallCount == 1)
        #expect(factory.downloadedVariants == [CueAppConfiguration.modelID])
        #expect(factory.makeClientModelIDs == [CueAppConfiguration.modelID])
        #expect(defaults.string(forKey: CueAppConfiguration.cachedModelPathDefaultsKey) == modelFolder.path)
    }

    @Test func prepareModelIgnoresProgressCallbacksAfterDownloadFinishes() async throws {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let modelFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent(CueAppConfiguration.expectedDownloadedModelFolderName(for: CueAppConfiguration.modelID))
        let factory = FakeWhisperKitClientFactory(downloadResult: modelFolder)
        factory.progressToReportDuringDownload = nil
        let service = WhisperKitTranscriptionService(defaults: defaults, clientFactory: factory)
        var statuses: [ModelPreparationStatus] = []
        service.statusHandler = { statuses.append($0) }

        try await service.prepareModel()

        let terminalStatuses = statuses
        #expect(terminalStatuses == [.checkingCache, .downloading(progress: nil), .loading, .ready])

        factory.capturedProgressHandler?(0.75)
        try await Task.sleep(nanoseconds: 10_000_000)

        #expect(statuses == terminalStatuses)
    }

    @Test func prepareModelIgnoresCachedPathForPreviousModelVariant() async throws {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let staleModelFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("openai_whisper-base.en")
        try FileManager.default.createDirectory(at: staleModelFolder, withIntermediateDirectories: true)
        defaults.set(staleModelFolder.path, forKey: CueAppConfiguration.cachedModelPathDefaultsKey)

        let currentModelFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent(CueAppConfiguration.expectedDownloadedModelFolderName(for: CueAppConfiguration.modelID))
        let factory = FakeWhisperKitClientFactory(downloadResult: currentModelFolder)
        let service = WhisperKitTranscriptionService(defaults: defaults, clientFactory: factory)

        try await service.prepareModel()

        #expect(factory.downloadCallCount == 1)
        #expect(factory.downloadedVariants == [CueAppConfiguration.modelID])
        #expect(factory.makeClientModelIDs == [CueAppConfiguration.modelID])
        #expect(defaults.string(forKey: CueAppConfiguration.cachedModelPathDefaultsKey) == currentModelFolder.path)
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

    @Test func debugCaptureStoreUsesInjectedDateUUIDAndTimeZoneForCapturePath() async throws {
        let captureRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: captureRoot) }

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
            rootDirectory: captureRoot,
            dateProvider: { fixedDate },
            uuidProvider: { fixedUUID },
            timeZone: timeZone
        )

        let capture = try await store.createCapture(audioSamples: [0], recordingDuration: 1.0)

        let expectedCaptureID = "2026-05-04T12-34-56.789Z-12345678-1234-5678-1234-567812345678"
        #expect(capture.captureID == expectedCaptureID)
        #expect(capture.directoryURL.lastPathComponent == expectedCaptureID)
        #expect(capture.directoryURL.deletingLastPathComponent().lastPathComponent == "2026-05-04")
        #expect(FileManager.default.fileExists(atPath: capture.directoryURL.appendingPathComponent("clip.wav").path))
    }

    @Test func debugCaptureStoreWritesTypedResultJSON() async throws {
        let captureRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: captureRoot) }

        let store = DebugCaptureStore(rootDirectory: captureRoot)
        let capture = try await store.createCapture(audioSamples: [0], recordingDuration: 1.0)

        try await store.saveResult(
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

        let resultData = try Data(contentsOf: capture.directoryURL.appendingPathComponent("result.json"))
        let document = try JSONDecoder().decode(DebugCaptureResultDocument.self, from: resultData)

        #expect(document.captureID == capture.captureID)
        #expect(document.sampleCount == 1)
        #expect(document.recordingDuration == 1.5)
        #expect(document.finalTranscript == "hello")
        #expect(document.errorMessage == nil)
        #expect(document.rawSegments == [
            DebugCaptureResultSegment(
                text: "hello",
                language: "en",
                modelLoadDuration: 0.25,
                pipelineDuration: 0.5
            )
        ])
    }

    @Test func debugCaptureStoreUsesInjectedSampleRateInWAVHeader() async throws {
        let captureRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: captureRoot) }

        let store = DebugCaptureStore(rootDirectory: captureRoot, sampleRate: 22_050)

        let capture = try await store.createCapture(audioSamples: [0, 0.5], recordingDuration: 1.0)
        let wavData = try Data(contentsOf: capture.directoryURL.appendingPathComponent("clip.wav"))

        #expect(littleEndianUInt32(in: wavData, at: 24) == 22_050)
        #expect(littleEndianUInt32(in: wavData, at: 28) == 44_100)
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
    var downloadedVariants: [String] = []
    var makeClientModelIDs: [String] = []
    var downloadResult: URL
    var downloadError: Error?
    var makeClientError: Error?
    var client: FakeWhisperKitClient
    var progressToReportDuringDownload: Double? = 0.5
    var capturedProgressHandler: ((Double) -> Void)?

    init(downloadResult: URL, client: FakeWhisperKitClient = FakeWhisperKitClient()) {
        self.downloadResult = downloadResult
        self.client = client
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
        _ = modelDirectory
        _ = modelFolder
        makeClientCallCount += 1
        makeClientModelIDs.append(modelID)

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

private func littleEndianUInt32(in data: Data, at offset: Int) -> UInt32 {
    precondition(offset + 4 <= data.count)

    var value: UInt32 = 0
    for byteOffset in 0..<4 {
        value |= UInt32(data[offset + byteOffset]) << UInt32(byteOffset * 8)
    }
    return value
}
