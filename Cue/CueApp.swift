import SwiftUI

@main
struct CueApp: App {
    @State private var model = CueAppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 760, minHeight: 680)
        }
    }
}
