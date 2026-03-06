import AppKit
import SwiftUI

struct CueMenuBarContentView: View {
    @Bindable var model: CueAppModel
    @Bindable var hotkeyManager: CueHotkeyManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Section {
            Label(model.menuBarPrimaryStatus, systemImage: model.menuBarSymbolName)

            if let secondaryStatus = model.menuBarSecondaryStatus {
                Text(secondaryStatus)
            }
        }

        Section("Push to Talk") {
            Text(hotkeyManager.shortcutSummary)
        }

        if let errorMessage = model.errorMessage {
            Section("Last Error") {
                Text(errorMessage)
            }
        }

        Divider()

        Button("Open Debug Window") {
            openWindow(id: CueSceneID.debugWindow)
        }

        if model.shouldOfferModelRetry {
            Button("Retry Model Preparation") {
                Task {
                    await model.retryModelPreparation()
                }
            }
        }

        Divider()

        Button("Quit Cue") {
            NSApplication.shared.terminate(nil)
        }
    }
}
