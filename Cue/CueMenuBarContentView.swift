import AppKit
import SwiftUI

struct CueMenuBarContentView: View {
    @Bindable var model: CueAppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let menu = model.presentation.menu

        Button(action: {}) {
            Label(menu.title, systemImage: model.menuBarSymbolName)
        }
        .disabled(true)

        Divider()

        ForEach(menu.actions, id: \.self) { action in
            Button(action.title) {
                perform(action)
            }
        }
    }

    private func perform(_ action: CueAppAction) {
        model.perform(action) {
            openWindow(id: CueSceneID.mainWindow)
        }
    }
}
