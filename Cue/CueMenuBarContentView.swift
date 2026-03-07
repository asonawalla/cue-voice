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

        if !model.isSetupComplete {
            Section("Setup") {
                permissionLine(for: .microphone)
                permissionLine(for: .paste)
            }
        } else {
            Section("Push to Talk") {
                Text(hotkeyManager.shortcutSummary)
            }

            if let insertionResult = model.lastInsertionResult {
                Section("Last Insertion") {
                    Text(insertionResult.targetAppName)
                    Text(insertionResult.clipboardRestoreOutcome.title)
                }
            }

            if let errorMessage = model.errorMessage {
                Section("Last Error") {
                    Text(errorMessage)
                }
            }
        }

        Divider()

        Button(model.windowButtonTitle) {
            openWindow(id: CueSceneID.mainWindow)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }

        if model.shouldOfferModelRetry {
            Button("Retry Model Preparation") {
                Task {
                    await model.retryModelPreparation()
                }
            }
        }

        if model.shouldOfferPastePermissionRecovery {
            Button("Relaunch Cue") {
                model.relaunchApplication()
            }
        }

        Divider()

        Button("Quit Cue") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func permissionLine(for permission: CuePermissionKind) -> some View {
        HStack {
            Text(permission.title)
            Spacer()
            Text(model.permissionSnapshot.state(for: permission).title)
                .foregroundStyle(.secondary)
        }
    }
}
