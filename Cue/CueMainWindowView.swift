import KeyboardShortcuts
import SwiftUI

struct CueMainWindowView: View {
    @Bindable var model: CueAppModel
    @Bindable var hotkeyManager: CueHotkeyManager
    @State private var isDiagnosticsExpanded = false

    var body: some View {
        ScrollView {
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
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .popoverBackground()
        .accessibilityIdentifier(CueAccessibilityID.mainWindowRoot)
        .animation(.easeInOut(duration: 0.2), value: model.needsPermissionPrompt)
        .animation(.easeInOut(duration: 0.2), value: model.shouldOfferModelRetry)
        .animation(.easeInOut(duration: 0.25), value: model.errorMessage != nil)
    }

    private var headerSection: some View {
        HStack(spacing: 14) {
            Image(systemName: model.menuBarSymbolName)
                .font(.system(size: 28))
                .foregroundStyle(CueTheme.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.menuBarPrimaryStatus)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(CueTheme.ink)

                if let secondary = model.menuBarSecondaryStatus {
                    Text(secondary)
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(CueTheme.slate)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
        .padding(CueTheme.cardPadding)
        .glassCard()
    }

    private var setupSection: some View {
        let presentation = model.presentation

        return VStack(alignment: .leading, spacing: 16) {
            if let micAction = presentation.microphonePermission.primaryAction {
                permissionRow(
                    title: "Microphone",
                    detail: presentation.microphonePermission.detail,
                    isGranted: model.permissionSnapshot.isMicrophoneReady,
                    primaryAction: micAction,
                    secondaryAction: presentation.microphonePermission.secondaryAction
                )
            }

            if let accessAction = presentation.accessibilityPermission.primaryAction {
                permissionRow(
                    title: "Accessibility",
                    detail: presentation.accessibilityPermission.detail,
                    isGranted: model.permissionSnapshot.isAccessibilityReady,
                    primaryAction: accessAction,
                    secondaryAction: presentation.accessibilityPermission.secondaryAction
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var readySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            primarySectionCard(title: "Push to Talk", accessibilityID: CueAccessibilityID.pushToTalkSection) {
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

            if let metrics = model.latencyMetrics {
                latencyMetricsCard(metrics)
            }

            secondarySectionCard(title: "Diagnostics", accessibilityID: CueAccessibilityID.diagnosticsSection) {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isDiagnosticsExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isDiagnosticsExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(CueTheme.slate)

                            Text("Debug transcription captures")
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(CueTheme.ink)

                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(CueAccessibilityID.diagnosticsDisclosure)
                    .accessibilityValue(isDiagnosticsExpanded ? "Expanded" : "Collapsed")

                    if isDiagnosticsExpanded {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(isOn: $model.debugCapturesEnabled) {
                                    Text("Save Debug Transcription Captures")
                                        .font(.system(.caption, design: .rounded).weight(.semibold))
                                        .foregroundStyle(CueTheme.ink)
                                }
                                .toggleStyle(.switch)

                                Text("Save audio clips and transcription results for troubleshooting.")
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(CueTheme.slate)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier(CueAccessibilityID.debugCapturesToggle)

                            HStack(spacing: 8) {
                                Button("Open Debug Captures Folder") {
                                    model.openDebugCapturesFolder()
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier(CueAccessibilityID.openDebugCapturesButton)

                                Button("Clear Saved Captures", role: .destructive) {
                                    model.clearDebugCaptures()
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier(CueAccessibilityID.clearDebugCapturesButton)
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            }
        }
    }

    private func latencyMetricsCard(_ metrics: LatencyMetrics) -> some View {
        secondarySectionCard(title: "Last Run") {
            VStack(alignment: .leading, spacing: 6) {
                latencyRow(label: "press → ack", value: metrics.pressToAck)
                latencyRow(label: "release → life", value: metrics.releaseToProofOfLife)
                latencyRow(label: "release → insert", value: metrics.releaseToInsert, emphasized: true)
                Divider()
                    .padding(.vertical, 2)
                latencyRow(label: "transcription", value: metrics.transcriptionDuration)
                latencyRow(label: "paste", value: metrics.pasteDuration)
            }
        }
    }

    private func latencyRow(label: String, value: TimeInterval, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(CueTheme.slate)
            Spacer(minLength: 8)
            Text("\(Int(value * 1000))ms")
                .font(.system(.caption2, design: .monospaced).weight(emphasized ? .semibold : .regular))
                .foregroundStyle(emphasized ? CueTheme.ink : CueTheme.slate)
        }
    }

    private func primarySectionCard<Content: View>(
        title: String,
        accessibilityID: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        sectionCard(
            title: title,
            titleFont: .system(.subheadline, design: .rounded).weight(.medium),
            titleColor: CueTheme.ink,
            accessibilityID: accessibilityID,
            content: content
        )
    }

    private func secondarySectionCard<Content: View>(
        title: String,
        accessibilityID: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        sectionCard(
            title: title,
            titleFont: .system(.caption, design: .rounded).weight(.semibold),
            titleColor: CueTheme.slate,
            accessibilityID: accessibilityID,
            content: content
        )
    }

    private func sectionCard<Content: View>(
        title: String,
        titleFont: Font,
        titleColor: Color,
        accessibilityID: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(titleFont)
                .foregroundStyle(titleColor)

            content()
        }
        .padding(CueTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .contain)
        .cueAccessibilityIdentifier(accessibilityID)
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
}

private extension View {
    @ViewBuilder
    func cueAccessibilityIdentifier(_ accessibilityID: String?) -> some View {
        if let accessibilityID {
            accessibilityIdentifier(accessibilityID)
        } else {
            self
        }
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
