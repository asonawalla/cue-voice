import Foundation
import WhisperKit

protocol DebugCaptureStoring: AnyObject {
    func createCapture(audioSamples: [Float], recordingDuration: TimeInterval) async throws -> DebugCaptureHandle
    func saveResult(
        for capture: DebugCaptureHandle,
        sampleCount: Int,
        recordingDuration: TimeInterval,
        segments: [WhisperKitTranscriptionSegment],
        finalTranscript: String,
        errorMessage: String?
    ) async throws
}

struct DebugCaptureHandle: Equatable, Sendable {
    let captureID: String
    let directoryURL: URL
}

struct DebugCaptureResultDocument: Codable, Equatable, Sendable {
    let captureID: String
    let sampleCount: Int
    let recordingDuration: TimeInterval
    let rawSegments: [DebugCaptureResultSegment]
    let finalTranscript: String
    let errorMessage: String?
}

struct DebugCaptureResultSegment: Codable, Equatable, Sendable {
    let text: String
    let language: String?
    let modelLoadDuration: TimeInterval
    let pipelineDuration: TimeInterval
}

final class DebugCaptureStore: DebugCaptureStoring, @unchecked Sendable {
    private let fileManager: FileManager
    private let rootDirectory: URL

    init(
        fileManager: FileManager = .default,
        rootDirectory: URL
    ) {
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory
    }

    func createCapture(audioSamples: [Float], recordingDuration: TimeInterval) async throws -> DebugCaptureHandle {
        _ = recordingDuration
        let fileManager = self.fileManager
        let rootDirectory = self.rootDirectory

        return try await Task.detached(priority: .utility) {
            let now = Date()
            let dayDirectory = rootDirectory.appendingPathComponent(Self.dayFolderName(for: now), isDirectory: true)
            let captureID = Self.makeCaptureID(from: now)
            let captureDirectory = dayDirectory.appendingPathComponent(captureID, isDirectory: true)

            try fileManager.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
            try Self.wavData(from: audioSamples).write(to: captureDirectory.appendingPathComponent("clip.wav"))

            return DebugCaptureHandle(captureID: captureID, directoryURL: captureDirectory)
        }.value
    }

    func saveResult(
        for capture: DebugCaptureHandle,
        sampleCount: Int,
        recordingDuration: TimeInterval,
        segments: [WhisperKitTranscriptionSegment],
        finalTranscript: String,
        errorMessage: String?
    ) async throws {
        let result = DebugCaptureResultDocument(
            captureID: capture.captureID,
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

        let resultURL = capture.directoryURL.appendingPathComponent("result.json")
        try await Task.detached(priority: .utility) {
            let jsonObject: [String: Any] = [
                "captureID": result.captureID,
                "sampleCount": result.sampleCount,
                "recordingDuration": result.recordingDuration,
                "rawSegments": result.rawSegments.map {
                    [
                        "text": $0.text,
                        "language": $0.language as Any,
                        "modelLoadDuration": $0.modelLoadDuration,
                        "pipelineDuration": $0.pipelineDuration
                    ]
                },
                "finalTranscript": result.finalTranscript,
                "errorMessage": result.errorMessage as Any
            ]

            let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: resultURL)
        }.value
    }

    nonisolated private static func makeCaptureID(from date: Date) -> String {
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.timeZone = TimeZone.current
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = timestampFormatter.string(from: date).replacingOccurrences(of: ":", with: "-")
        return "\(timestamp)-\(UUID().uuidString.lowercased())"
    }

    nonisolated private static func dayFolderName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    nonisolated private static func wavData(from audioSamples: [Float]) throws -> Data {
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
        appendLittleEndian(UInt32(WhisperKit.sampleRate))
        appendLittleEndian(UInt32(WhisperKit.sampleRate * bytesPerSample))
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
