import AppKit
import SwiftUI

@main
struct CueApp: App {
    @State private var cue: Cue
    @State private var launchAtLogin = LaunchAtLogin()

    init() {
        let cue = Cue()
        _cue = State(initialValue: cue)
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            Task { await cue.run() }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            CueMenu(cue: cue, launchAtLogin: launchAtLogin)
        } label: {
            if cue.status == .ready {
                Image("MenuBarRibbonQ")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .accessibilityLabel(cue.status.message)
            } else {
                Image(systemName: cue.status.symbolName)
                    .accessibilityLabel(cue.status.message)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct CueMenu: View {
    let cue: Cue
    let launchAtLogin: LaunchAtLogin

    var body: some View {
        Group {
            Text(cue.status.message)
            Divider()
            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { launchAtLogin.isRegistered },
                    set: { launchAtLogin.setEnabled($0) }
                )
            )
            if launchAtLogin.requiresApproval {
                Button("Approve Login Item in System Settings…") {
                    launchAtLogin.openApprovalSettings()
                }
            }
            if let errorMessage = launchAtLogin.errorMessage {
                Text(errorMessage)
            }
            Divider()
            Button("About Cue") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                NSApplication.shared.orderFrontStandardAboutPanel(nil)
            }
            Button("Quit Cue") {
                NSApplication.shared.terminate(nil)
            }
        }
        .onAppear {
            launchAtLogin.refresh()
        }
    }
}
