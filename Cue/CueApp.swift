import AppKit
import SwiftUI

@main
struct CueApp: App {
    @State private var model: CueAppModel
    @State private var triggerManager: CueTriggerManager

    init() {
        let environment = CueAppEnvironment.make()
        let model = environment.model
        let triggerManager = environment.triggerManager

        _model = State(initialValue: model)
        _triggerManager = State(initialValue: triggerManager)

        Task { @MainActor in
            if CueAppEnvironment.isUITesting || model.needsPermissionPrompt {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }

            await model.launch()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            CueMenuBarContentView(model: model)
        } label: {
            CueMenuBarLabelView(model: model)
        }
        .menuBarExtraStyle(.menu)

        Window("Finish Setup", id: CueSceneID.permissionsWindow) {
            CuePermissionsPromptView(model: model)
        }
        .defaultSize(width: 460, height: 560)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(model.needsPermissionPrompt ? .presented : .suppressed)

        Window("Cue", id: CueSceneID.mainWindow) {
            ContentView(model: model, triggerManager: triggerManager)
                .frame(minWidth: 760, minHeight: 760)
        }
        .defaultSize(width: 900, height: 820)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(CueAppEnvironment.isUITesting ? .presented : .suppressed)
    }
}

private struct CueMenuBarLabelView: View {
    @Bindable var model: CueAppModel

    var body: some View {
        Image(systemName: model.menuBarSymbolName)
            .accessibilityLabel(model.menuBarPrimaryStatus)
    }
}
