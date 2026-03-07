import AppKit
import SwiftUI

@main
struct CueApp: App {
    @State private var model: CueAppModel
    @State private var hotkeyManager: CueHotkeyManager

    init() {
        let model = CueAppModel()
        let hotkeyManager = CueHotkeyManager(appModel: model)

        _model = State(initialValue: model)
        _hotkeyManager = State(initialValue: hotkeyManager)

        Task { @MainActor in
            if model.needsPermissionPrompt {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }

            await model.launch()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            CueMenuBarContentView(model: model, hotkeyManager: hotkeyManager)
        } label: {
            CueMenuBarLabelView(model: model)
        }
        .menuBarExtraStyle(.menu)

        Window("Finish Setup", id: CueSceneID.permissionsWindow) {
            CuePermissionsPromptView(model: model)
        }
        .defaultSize(width: 460, height: 420)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(model.needsPermissionPrompt ? .presented : .suppressed)

        Window("Cue", id: CueSceneID.mainWindow) {
            ContentView(model: model, hotkeyManager: hotkeyManager)
                .frame(minWidth: 760, minHeight: 760)
        }
        .defaultLaunchBehavior(.suppressed)
    }
}

private struct CueMenuBarLabelView: View {
    @Bindable var model: CueAppModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: model.menuBarSymbolName)
                .accessibilityLabel(model.menuBarPrimaryStatus)

            if model.showsAutomaticPasteIndicator {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 7, height: 7)
                    .offset(x: 3, y: -2)
            }
        }
    }
}
