import AppKit
import SwiftUI

@main
struct CueApp: App {
    @State private var cue: Cue

    init() {
        let cue = Cue()
        _cue = State(initialValue: cue)
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            Task { await cue.run() }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            Text(cue.status.message)
            Divider()
            Button("Quit Cue") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: cue.status.symbolName)
                .accessibilityLabel(cue.status.message)
        }
        .menuBarExtraStyle(.menu)
    }
}
