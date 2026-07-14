import AppKit
import SwiftUI

private let cueMainWindowID = "cue.main-window"

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

        Window("Cue", id: cueMainWindowID) {
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
        let presentation = model.presentation

        Text(presentation.menuBarPrimaryStatus)

        if let secondaryStatus = presentation.menuBarSecondaryStatus {
            Text(secondaryStatus)
        }

        Divider()

        Button("Open Cue") {
            openWindow(id: cueMainWindowID)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        .accessibilityIdentifier(CueAccessibilityID.openCueMenuItem)

        Divider()

        Button("Quit Cue") {
            NSApplication.shared.terminate(nil)
        }
    }
}

private struct CueMenuBarLabelView: View {
    @Bindable var model: CueAppModel

    var body: some View {
        let presentation = model.presentation

        Image(systemName: presentation.menuBarSymbolName)
            .accessibilityLabel(presentation.menuBarPrimaryStatus)
            .accessibilityIdentifier(CueAccessibilityID.menuBarTrigger)
    }
}
