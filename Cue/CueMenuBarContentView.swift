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

        if !model.isReadyToRecord {
            Section("Setup") {
                microphonePermissionLine
                accessibilityPermissionLine
            }
        } else {
            if let automationWarningMessage = model.automaticPasteWarningMessage {
                Section("Automation") {
                    Text(automationWarningMessage)
                    accessibilityPermissionLine
                }
            }

            Section("Push to Talk") {
                Text(hotkeyManager.shortcutSummary)
            }

            if let insertionResult = model.lastInsertionResult {
                Section("Last Insertion") {
                    Text(insertionResult.delivery.title)

                    if let targetAppName = insertionResult.targetAppName {
                        Text(targetAppName)
                    }

                    Text(insertionResult.delivery.detail)
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

        if !model.permissionSnapshot.canAutoPaste {
            Button("Enable Automatic Paste") {
                Task {
                    await model.requestPastePermission()
                }
            }

            Button("Open Accessibility Settings") {
                model.openAccessibilitySettings()
            }
        }

        Divider()

        Button("Quit Cue") {
            NSApplication.shared.terminate(nil)
        }
    }

    private var microphonePermissionLine: some View {
        HStack {
            Text(CuePermissionKind.microphone.title)
            Spacer()
            Text(model.permissionSnapshot.microphone.title)
                .foregroundStyle(.secondary)
        }
    }

    private var accessibilityPermissionLine: some View {
        HStack {
            Text(CuePermissionKind.paste.title)
            Spacer()
            Text(model.permissionSnapshot.paste.title)
                .foregroundStyle(.secondary)
        }
    }
}
