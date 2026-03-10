import KeyboardShortcuts
import SwiftUI

struct CuePopoverView: View {
    @Bindable var model: CueAppModel
    @Bindable var hotkeyManager: CueHotkeyManager
    @State private var isQuitHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                headerSection

                Group {
                    if model.needsPermissionPrompt {
                        setupSection
                    } else if model.shouldOfferModelRetry {
                        modelRetrySection
                    } else {
                        readySection
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))

                if let errorMessage = model.errorMessage {
                    errorSection(message: errorMessage)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(CueTheme.popoverPadding)

            Divider()
                .padding(.horizontal, CueTheme.popoverPadding)

            quitButton
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
        }
        .frame(width: 320)
        .popoverBackground()
        .accessibilityIdentifier(CueAccessibilityID.popoverRoot)
        .animation(.easeInOut(duration: 0.2), value: model.needsPermissionPrompt)
        .animation(.easeInOut(duration: 0.2), value: model.shouldOfferModelRetry)
        .animation(.easeInOut(duration: 0.25), value: model.errorMessage != nil)
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
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isGranted)

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
        .padding(CueTheme.cardPadding)
        .glassCard()
    }

    private var readySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Push to Talk")
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(CueTheme.ink)

            VStack(spacing: 0) {
                KeyboardShortcuts.Recorder("Shortcut", name: .pushToTalk) { shortcut in
                    hotkeyManager.updateShortcutSummary(shortcut)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(CueAccessibilityID.shortcutRecorder)

            Text(
                hotkeyManager.hasConfiguredShortcut
                    ? "Hold \(hotkeyManager.shortcutSummary) in any app to record."
                    : "Set a shortcut to enable push-to-talk."
            )
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(CueTheme.slate)
        }
        .padding(CueTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CueAccessibilityID.pushToTalkSection)
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
        .padding(CueTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardTinted(tintColor: CueTheme.errorInk.opacity(0.3))
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
        .glassCardTinted(tintColor: CueTheme.errorInk.opacity(0.2), cornerRadius: CueTheme.errorCornerRadius)
    }

    private var quitButton: some View {
        Button {
            model.perform(.quit)
        } label: {
            HStack {
                Text("Quit Cue")
                Spacer()
            }
        }
        .accessibilityIdentifier(CueAccessibilityID.quitButton)
        .buttonStyle(CueFooterActionButtonStyle(isHovered: isQuitHovered))
        .onHover { isHovering in
            isQuitHovered = isHovering
        }
    }
}

private struct CueFooterActionButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(isHovered || configuration.isPressed ? CueTheme.ink : CueTheme.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: CueTheme.footerActionCornerRadius, style: .continuous)
                    .fill(backgroundFill(isPressed: configuration.isPressed))
                    .overlay {
                        RoundedRectangle(cornerRadius: CueTheme.footerActionCornerRadius, style: .continuous)
                            .strokeBorder(borderColor(isPressed: configuration.isPressed), lineWidth: 1)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: CueTheme.footerActionCornerRadius, style: .continuous))
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .animation(.easeInOut(duration: 0.08), value: configuration.isPressed)
    }

    private func backgroundFill(isPressed: Bool) -> Color {
        let base = Color(nsColor: .selectedContentBackgroundColor)
        if isPressed {
            return base.opacity(0.30)
        }
        if isHovered {
            return base.opacity(0.22)
        }
        return base.opacity(0.10)
    }

    private func borderColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color(nsColor: .separatorColor).opacity(0.40)
        }
        if isHovered {
            return Color(nsColor: .separatorColor).opacity(0.28)
        }
        return Color(nsColor: .separatorColor).opacity(0.18)
    }
}

#if DEBUG
struct CueGlassPreviewHelper: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Glass Card Styles")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Regular Glass Card")
                    .font(.subheadline)
                Text("This card uses Liquid Glass on macOS 26+ or ultraThinMaterial fallback")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()

            VStack(alignment: .leading, spacing: 8) {
                Text("Tinted Glass Card (Error)")
                    .font(.subheadline)
                Text("This card shows error styling with red tint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCardTinted(tintColor: .red.opacity(0.3))

            VStack(alignment: .leading, spacing: 8) {
                Text("Tinted Glass Card (Success)")
                    .font(.subheadline)
                Text("This card shows success styling with green tint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCardTinted(tintColor: .green.opacity(0.3))
        }
        .padding(20)
        .frame(width: 320)
        .popoverBackground()
    }
}

#Preview("Glass Styles") {
    CueGlassPreviewHelper()
        .preferredColorScheme(.light)
}

#Preview("Glass Styles - Dark") {
    CueGlassPreviewHelper()
        .preferredColorScheme(.dark)
}
#endif
