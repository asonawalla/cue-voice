import Foundation
import WhisperKit

nonisolated protocol DebugCaptureStoring: AnyObject {
    func createCapture(audioSamples: [Float]) async throws -> URL
    func saveResult(
        for captureDirectory: URL,
        sampleCount: Int,
        recordingDuration: TimeInterval,
        segments: [WhisperKitTranscriptionSegment],
        finalTranscript: String,
        errorMessage: String?
    ) async throws
}

nonisolated struct DebugCaptureResultDocument: Codable, Sendable {
    let captureID: String
    let sampleCount: Int
    let recordingDuration: TimeInterval
    let rawSegments: [DebugCaptureResultSegment]
    let finalTranscript: String
    let errorMessage: String?
}

nonisolated struct DebugCaptureResultSegment: Codable, Equatable, Sendable {
    let text: String
    let language: String?
    let modelLoadDuration: TimeInterval
    let pipelineDuration: TimeInterval
}

actor DebugCaptureStore: DebugCaptureStoring {
    private let rootDirectory: URL
    private let dateProvider: @Sendable () -> Date
    private let uuidProvider: @Sendable () -> UUID
    private let timeZone: TimeZone
    private let sampleRate: Int

    init(
        rootDirectory: URL,
        dateProvider: @escaping @Sendable () -> Date = Date.init,
        uuidProvider: @escaping @Sendable () -> UUID = UUID.init,
        timeZone: TimeZone = .current,
        sampleRate: Int = WhisperKit.sampleRate
    ) {
        self.rootDirectory = rootDirectory
        self.dateProvider = dateProvider
        self.uuidProvider = uuidProvider
        self.timeZone = timeZone
        self.sampleRate = sampleRate
    }

    func createCapture(audioSamples: [Float]) async throws -> URL {
        let now = dateProvider()
        let dayDirectory = rootDirectory.appendingPathComponent(
            Self.dayFolderName(for: now, timeZone: timeZone),
            isDirectory: true
        )
        let captureID = Self.makeCaptureID(
            from: now,
            uuid: uuidProvider(),
            timeZone: timeZone
        )
        let captureDirectory = dayDirectory.appendingPathComponent(captureID, isDirectory: true)

        try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        try Self.wavData(from: audioSamples, sampleRate: sampleRate)
            .write(to: captureDirectory.appendingPathComponent("clip.wav"))

        return captureDirectory
    }

    func saveResult(
        for captureDirectory: URL,
        sampleCount: Int,
        recordingDuration: TimeInterval,
        segments: [WhisperKitTranscriptionSegment],
        finalTranscript: String,
        errorMessage: String?
    ) async throws {
        let result = DebugCaptureResultDocument(
            captureID: captureDirectory.lastPathComponent,
            sampleCount: sampleCount,
            recordingDuration: recordingDuration,
            rawSegments: segments.map {
                DebugCaptureResultSegment(
                    text: $0.text,
                    language: $0.language,
                    modelLoadDuration: $0.modelLoadDuration,
                    pipelineDuration: $0.pipelineDuration
                )
            },
            finalTranscript: finalTranscript,
            errorMessage: errorMessage
        )

        let resultURL = captureDirectory.appendingPathComponent("result.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)
        try data.write(to: resultURL)
    }

    nonisolated private static func makeCaptureID(from date: Date, uuid: UUID, timeZone: TimeZone) -> String {
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.timeZone = timeZone
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = timestampFormatter.string(from: date).replacingOccurrences(of: ":", with: "-")
        return "\(timestamp)-\(uuid.uuidString.lowercased())"
    }

    nonisolated private static func dayFolderName(for date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    nonisolated private static func wavData(from audioSamples: [Float], sampleRate: Int) throws -> Data {
        let bytesPerSample = 2
        let dataChunkSize = audioSamples.count * bytesPerSample
        guard dataChunkSize <= Int(UInt32.max) - 36 else {
            throw CocoaError(.fileWriteOutOfSpace)
        }

        var data = Data()
        func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
            var littleEndianValue = value.littleEndian
            Swift.withUnsafeBytes(of: &littleEndianValue) { bytes in
                data.append(contentsOf: bytes)
            }
        }

        data.append(contentsOf: Array("RIFF".utf8))
        appendLittleEndian(UInt32(36 + dataChunkSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendLittleEndian(UInt32(16))
        appendLittleEndian(UInt16(1))
        appendLittleEndian(UInt16(1))
        appendLittleEndian(UInt32(sampleRate))
        appendLittleEndian(UInt32(sampleRate * bytesPerSample))
        appendLittleEndian(UInt16(bytesPerSample))
        appendLittleEndian(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        appendLittleEndian(UInt32(dataChunkSize))

        for sample in audioSamples {
            let clampedSample = max(-1, min(1, sample))
            let pcmValue = Int16((clampedSample * Float(Int16.max)).rounded())
            appendLittleEndian(pcmValue)
        }

        return data
    }
}
