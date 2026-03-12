import Foundation

enum CueAppConfiguration {
    nonisolated static let bundleIdentifier = "dev.sonawalla.Cue"
    nonisolated static let modelID = "small.en"
    nonisolated static let minimumRecordingDuration: TimeInterval = 0.35
    nonisolated static let cachedModelPathDefaultsKey = "Cue.cachedWhisperModelPath"
    nonisolated static let debugCapturesEnabledDefaultsKey = "Cue.debugCapturesEnabled"
    nonisolated static let uiTestingLaunchArgument = "--ui-testing"

    nonisolated static func modelDownloadDirectory(fileManager: FileManager = .default) -> URL {
        appDirectory(in: .applicationSupportDirectory, fileManager: fileManager)
            .appendingPathComponent("Models", isDirectory: true)
    }

    nonisolated static func debugCaptureRootDirectory(fileManager: FileManager = .default) -> URL {
        appDirectory(in: .cachesDirectory, fileManager: fileManager)
            .appendingPathComponent("DebugCaptures", isDirectory: true)
    }

    nonisolated static func debugCaptureDisplayPath(fileManager: FileManager = .default) -> String {
        NSString(string: debugCaptureRootDirectory(fileManager: fileManager).path).abbreviatingWithTildeInPath
    }

    nonisolated private static func appDirectory(
        in searchPathDirectory: FileManager.SearchPathDirectory,
        fileManager: FileManager
    ) -> URL {
        let directoryURL = fileManager.urls(for: searchPathDirectory, in: .userDomainMask)[0]
        return directoryURL.appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    nonisolated static func expectedDownloadedModelFolderName(for modelID: String) -> String {
        "openai_whisper-\(modelID)"
    }
}
