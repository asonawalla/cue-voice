import KeyboardShortcuts
import SwiftUI

struct CuePopoverView: View {
    @Bindable var model: CueAppModel
    @Bindable var hotkeyManager: CueHotkeyManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection

            if model.needsPermissionPrompt {
                setupSection
            } else if model.shouldOfferModelRetry {
                modelRetrySection
            } else {
                readySection
            }

            if let errorMessage = model.errorMessage {
                errorSection(message: errorMessage)
            }

            Divider()
            quitButton
        }
        .padding(20)
        .frame(width: 320)
    }

    private var headerSection: some View {
        HStack {
            Image(systemName: model.menuBarSymbolName)
                .font(.system(size: 24))
                .foregroundStyle(CueTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.menuBarPrimaryStatus)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(CueTheme.ink)

                if let secondary = model.menuBarSecondaryStatus {
                    Text(secondary)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(CueTheme.slate)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
    }

    private var setupSection: some View {
        let setup = model.presentation.setup

        return VStack(alignment: .leading, spacing: 16) {
            if let micAction = setup.microphone.primaryAction {
                permissionRow(
                    title: "Microphone",
                    detail: setup.microphone.detail,
                    isGranted: model.permissionSnapshot.isMicrophoneReady,
                    primaryAction: micAction,
                    secondaryAction: setup.microphone.secondaryAction
                )
            }

            if let accessAction = setup.accessibility.primaryAction {
                permissionRow(
                    title: "Accessibility",
                    detail: setup.accessibility.detail,
                    isGranted: model.permissionSnapshot.isAccessibilityReady,
                    primaryAction: accessAction,
                    secondaryAction: setup.accessibility.secondaryAction
                )
            }
        }
    }

    private func permissionRow(
        title: String,
        detail: String,
        isGranted: Bool,
        primaryAction: CueAppAction,
        secondaryAction: CueAppAction?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: isGranted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isGranted ? CueTheme.success : CueTheme.slate)

                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(CueTheme.ink)

                Spacer()
            }

            if !isGranted {
                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(CueTheme.slate)

                HStack(spacing: 8) {
                    Button(primaryAction.title) {
                        model.perform(primaryAction)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CueTheme.accent)

                    if let secondaryAction {
                        Button(secondaryAction.title) {
                            model.perform(secondaryAction)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.8))
        )
    }

    private var readySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Push to Talk")
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(CueTheme.ink)

            KeyboardShortcuts.Recorder("Shortcut", name: .pushToTalk) { shortcut in
                hotkeyManager.updateShortcutSummary(shortcut)
            }

            Text(
                hotkeyManager.hasConfiguredShortcut
                    ? "Hold \(hotkeyManager.shortcutSummary) in any app to record."
                    : "Set a shortcut to enable push-to-talk."
            )
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(CueTheme.slate)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.8))
        )
    }

    private var modelRetrySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model Preparation Failed")
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(CueTheme.errorInk)

            Text("The speech recognition model could not be loaded.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(CueTheme.slate)

            Button("Retry Model Preparation") {
                model.perform(.retryModelPreparation)
            }
            .buttonStyle(.borderedProminent)
            .tint(CueTheme.accent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.98, green: 0.91, blue: 0.90))
        )
    }

    private func errorSection(message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Error")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(CueTheme.errorInk)

            Text(message)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(CueTheme.errorText)
                .lineLimit(3)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.98, green: 0.91, blue: 0.90).opacity(0.6))
        )
    }

    private var quitButton: some View {
        Button("Quit Cue") {
            model.perform(.quit)
        }
        .buttonStyle(.plain)
        .font(.system(.caption, design: .rounded))
        .foregroundStyle(CueTheme.muted)
    }
}
