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

        Window("Cue", id: CueSceneID.mainWindow) {
            ContentView(model: model, hotkeyManager: hotkeyManager)
                .frame(minWidth: 760, minHeight: 760)
        }
        .defaultLaunchBehavior(.suppressed)
    }
}

private struct CueMenuBarLabelView: View {
    @Bindable var model: CueAppModel
    @Environment(\.openWindow) private var openWindow
    @State private var lastHandledSetupWindowRequest = 0

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
        .task {
            presentSetupWindowIfNeeded()
        }
        .onChange(of: model.setupWindowPresentationToken) { _, _ in
            presentSetupWindowIfNeeded()
        }
    }

    private func presentSetupWindowIfNeeded() {
        guard model.setupWindowPresentationToken > lastHandledSetupWindowRequest else {
            return
        }

        lastHandledSetupWindowRequest = model.setupWindowPresentationToken
        focusSetupWindow()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            focusSetupWindow()
        }
    }

    private func focusSetupWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: CueSceneID.mainWindow)

        if let cueWindow = NSApplication.shared.windows.first(where: { $0.title == "Cue" }) {
            cueWindow.makeKeyAndOrderFront(nil)
            cueWindow.orderFrontRegardless()
        }
    }
}
