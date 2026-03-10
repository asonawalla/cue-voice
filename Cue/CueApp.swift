import AppKit
import SwiftUI

@main
struct CueApp: App {
    @State private var model: CueAppModel
    @State private var hotkeyManager: CueHotkeyManager

    init() {
        let environment = CueAppEnvironment.make()
        let model = environment.model
        let hotkeyManager = environment.hotkeyManager

        _model = State(initialValue: model)
        _hotkeyManager = State(initialValue: hotkeyManager)

        Task { @MainActor in
            if CueAppEnvironment.isUITesting || model.needsPermissionPrompt {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }

            await model.launch()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            CuePopoverView(model: model, hotkeyManager: hotkeyManager)
        } label: {
            CueMenuBarLabelView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct CueMenuBarLabelView: View {
    @Bindable var model: CueAppModel

    var body: some View {
        Image(systemName: model.menuBarSymbolName)
            .accessibilityLabel(model.menuBarPrimaryStatus)
            .accessibilityIdentifier(CueAccessibilityID.menuBarTrigger)
    }
}
