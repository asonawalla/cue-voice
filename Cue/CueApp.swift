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
            await model.launch()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            CueMenuBarContentView(model: model, hotkeyManager: hotkeyManager)
        } label: {
            Image(systemName: model.menuBarSymbolName)
                .accessibilityLabel(model.menuBarPrimaryStatus)
        }
        .menuBarExtraStyle(.menu)

        Window("Cue Debug", id: CueSceneID.debugWindow) {
            ContentView(model: model, hotkeyManager: hotkeyManager)
                .frame(minWidth: 760, minHeight: 760)
        }
        .defaultLaunchBehavior(.suppressed)
    }
}
