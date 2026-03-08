import Foundation

enum CueAppConfiguration {
    static let modelID = "base.en"
    static let minimumRecordingDuration: TimeInterval = 0.35
    static let cachedModelPathDefaultsKey = "Cue.cachedWhisperModelPath"
    static let uiTestingLaunchArgument = "--ui-testing"

    static var modelDownloadDirectory: URL {
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupportURL
            .appendingPathComponent("Cue", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }
}
