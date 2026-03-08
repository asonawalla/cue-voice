import SwiftUI

struct CuePermissionsPromptView: View {
    @Bindable var model: CueAppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            statusSection
            microphoneSection
            inputMonitoringSection
            accessibilitySection

            if !model.needsPermissionPrompt {
                footerButton(title: "Done") {
                    dismiss()
                }
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.98, green: 0.99, blue: 1.00))
                .shadow(color: Color.black.opacity(0.10), radius: 18, y: 10)
        )
        .padding(20)
        .accessibilityIdentifier("cue.permissions.root")
    }

    private var presentation: CueAppPresentation {
        model.presentation
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Finish Setup")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(CueTheme.ink)

            Text("Cue needs microphone, Input Monitoring, and Accessibility before push-to-talk can run fully.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(CueTheme.slate)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow(
                title: CuePermissionKind.microphone.title,
                value: model.permissionSnapshot.microphone.title,
                isPositive: model.permissionSnapshot.microphone.isGranted
            )

            statusRow(
                title: CuePermissionKind.inputMonitoring.title,
                value: model.permissionSnapshot.inputMonitoring.title,
                isPositive: model.permissionSnapshot.inputMonitoring.isGranted
            )

            statusRow(
                title: CuePermissionKind.accessibility.title,
                value: model.permissionSnapshot.accessibility.title,
                isPositive: model.permissionSnapshot.canAutoPaste
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sectionBackground)
    }

    private var microphoneSection: some View {
        let section = presentation.setup.microphone

        return VStack(alignment: .leading, spacing: 10) {
            Text("Microphone")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(CueTheme.ink)

            Text(section.detail)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(CueTheme.slate)

            if let primaryAction = section.primaryAction {
                footerButton(title: primaryAction.title) {
                    model.perform(primaryAction)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sectionBackground)
    }

    private var inputMonitoringSection: some View {
        let section = presentation.setup.inputMonitoring

        return VStack(alignment: .leading, spacing: 10) {
            Text("Input Monitoring")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(CueTheme.ink)

            Text(section.detail)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(CueTheme.slate)

            if let primaryAction = section.primaryAction {
                footerButton(title: primaryAction.title) {
                    model.perform(primaryAction)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sectionBackground)
    }

    private var accessibilitySection: some View {
        let section = presentation.setup.accessibility

        return VStack(alignment: .leading, spacing: 10) {
            Text("Accessibility")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(CueTheme.ink)

            Text(section.detail)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(CueTheme.slate)

            if let primaryAction = section.primaryAction {
                footerButton(title: primaryAction.title) {
                    model.perform(primaryAction)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sectionBackground)
    }

    private func statusRow(title: String, value: String, isPositive: Bool) -> some View {
        HStack {
            Text(title)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(CueTheme.ink)

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(isPositive ? CueTheme.success : CueTheme.warning)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill((isPositive ? CueTheme.success : CueTheme.warning).opacity(0.12))
                )
        }
    }

    private func footerButton(title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .tint(CueTheme.accent)
    }

    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.94))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.96), lineWidth: 1)
            )
    }
}
