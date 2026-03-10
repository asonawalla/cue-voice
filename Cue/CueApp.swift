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
            await model.launch()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            CueMenuBarMenuView(model: model)
        } label: {
            CueMenuBarLabelView(model: model)
        }
        .menuBarExtraStyle(.menu)

        Window("Cue", id: CueSceneID.mainWindow) {
            CueMainWindowView(model: model, hotkeyManager: hotkeyManager)
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 420, height: 520)
    }
}

private struct CueMenuBarMenuView: View {
    @Bindable var model: CueAppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.menuBarPrimaryStatus)

        if let secondaryStatus = model.menuBarSecondaryStatus {
            Text(secondaryStatus)
        }

        Divider()

        Button("Open Cue") {
            openWindow(id: CueSceneID.mainWindow)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        .accessibilityIdentifier(CueAccessibilityID.openCueMenuItem)

        Divider()

        Button("Quit Cue") {
            model.perform(.quit)
        }
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
