import Observation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var status = SMAppService.mainApp.status
    private(set) var errorMessage: String?

    var isRegistered: Bool {
        status == .enabled || status == .requiresApproval
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ isEnabled: Bool) {
        errorMessage = nil

        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = "Cue could not update Launch at Login: \(error.localizedDescription)"
        }

        refresh()
    }
}
