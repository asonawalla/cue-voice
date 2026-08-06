import Observation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLogin {
    private let service = SMAppService.mainApp

    private(set) var status: SMAppService.Status
    private(set) var errorMessage: String?

    init() {
        status = service.status
    }

    var isRegistered: Bool {
        status == .enabled || status == .requiresApproval
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    func refresh() {
        status = service.status
    }

    func setEnabled(_ isEnabled: Bool) {
        errorMessage = nil

        do {
            if isEnabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            errorMessage = "Cue could not update Launch at Login: \(error.localizedDescription)"
        }

        refresh()
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
