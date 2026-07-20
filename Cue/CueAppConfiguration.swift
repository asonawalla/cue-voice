import Foundation

enum CueAppConfiguration {
    nonisolated static let bundleIdentifier = "dev.sonawalla.Cue"
    nonisolated static let modelID = "small.en"
    nonisolated static let minimumRecordingDuration: TimeInterval = 0.35
    nonisolated static let cachedModelPathDefaultsKey = "Cue.cachedWhisperModelPath"
    nonisolated static let debugCapturesEnabledDefaultsKey = "Cue.debugCapturesEnabled"

    nonisolated static func modelDownloadDirectory() -> URL {
        appDirectory(in: .applicationSupportDirectory)
            .appendingPathComponent("Models", isDirectory: true)
    }

    nonisolated static func debugCaptureRootDirectory() -> URL {
        appDirectory(in: .cachesDirectory)
            .appendingPathComponent("DebugCaptures", isDirectory: true)
    }

    nonisolated private static func appDirectory(in searchPathDirectory: FileManager.SearchPathDirectory) -> URL {
        let directoryURL = FileManager.default.urls(for: searchPathDirectory, in: .userDomainMask)[0]
        return directoryURL.appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    nonisolated static func expectedDownloadedModelFolderName(for modelID: String) -> String {
        "openai_whisper-\(modelID)"
    }
}
