import KeyboardShortcuts
import SwiftUI

struct ContentView: View {
    @Bindable var model: CueAppModel
    @Bindable var hotkeyManager: CueHotkeyManager

    var body: some View {
        ZStack {
            CueTheme.backgroundGradient
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    permissionsOverviewCard

                    if let automationWarningMessage = model.automaticPasteWarningMessage {
                        automationWarningCard(message: automationWarningMessage)
                    }

                    permissionCards
                    statusCard
                    shortcutCard
                    transcriptCard
                    insertionCard
                    metricsCard

                    if let errorMessage = model.errorMessage {
                        errorCard(message: errorMessage)
                    }

                    detailsFooter
                }
                .padding(28)
                .accessibilityIdentifier("cue.mainWindow.root")
            }
        }
    }

    private var presentation: CueAppPresentation {
        model.presentation
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cue")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(CueTheme.ink)
                .accessibilityIdentifier("cue.mainWindow.title")

            Text(headerSubtitle)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(CueTheme.slate)
        }
    }

    private var headerSubtitle: String {
        "Menu bar push-to-talk prototype with a debug window for permissions, transcript delivery, and timing details."
    }

    private var permissionsOverviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Permissions")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(CueTheme.ink)

            if model.hasLoadedPermissionSnapshot {
                Text(presentation.setup.statusSummary)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(CueTheme.slate)

                Text("Cue checks permissions at launch. Microphone is required for dictation, and Accessibility is optional for automatic paste after Cue restarts.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(CueTheme.muted)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(CueTheme.accent)

                    Text("Cue is checking the current permission state.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(CueTheme.slate)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var permissionCards: some View {
        HStack(alignment: .top, spacing: 16) {
            microphoneCard
            accessibilityCard
        }
    }

    private var microphoneCard: some View {
        let state = model.permissionSnapshot.microphone
        let section = presentation.setup.microphone

        return VStack(alignment: .leading, spacing: 14) {
            cardHeader(
                title: CuePermissionKind.microphone.title,
                summary: CuePermissionKind.microphone.requirementSummary,
                statusTitle: state.title,
                isPositive: state.isGranted
            )

            Text(CuePermissionKind.microphone.systemSettingsPath)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(CueTheme.muted)

            Text(section.detail)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(CueTheme.muted)

            if let primaryAction = section.primaryAction {
                prominentActionButton(primaryAction)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var accessibilityCard: some View {
        let state = model.permissionSnapshot.accessibility
        let section = presentation.setup.accessibility

        return VStack(alignment: .leading, spacing: 14) {
            cardHeader(
                title: CuePermissionKind.accessibility.title,
                summary: CuePermissionKind.accessibility.requirementSummary,
                statusTitle: state.title,
                isPositive: state.isGranted
            )

            Text(CuePermissionKind.accessibility.systemSettingsPath)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(CueTheme.muted)

            Text(section.detail)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(CueTheme.muted)

            if let primaryAction = section.primaryAction {
                HStack(spacing: 10) {
                    prominentActionButton(primaryAction)

                    if let secondaryAction = section.secondaryAction {
                        secondaryActionButton(secondaryAction)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func cardHeader(title: String, summary: String, statusTitle: String, isPositive: Bool) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(CueTheme.ink)

                Text(summary)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(CueTheme.slate)
            }

            Spacer(minLength: 12)

            Text(statusTitle)
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

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Status")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(CueTheme.ink)

            HStack {
                statusTile(title: "Phase", value: model.sessionState.title)
                statusTile(title: "Model", value: model.modelStatus.title)
                statusTile(title: "Auto Paste", value: model.permissionSnapshot.accessibility.title)
            }

            if let progressValue = model.modelStatus.progressValue {
                ProgressView(value: progressValue)
                    .tint(CueTheme.accent)
            } else if model.isModelPreparing {
                ProgressView()
                    .controlSize(.small)
                    .tint(CueTheme.accent)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var shortcutCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Push to Talk")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(CueTheme.ink)

            KeyboardShortcuts.Recorder("Global shortcut", name: .pushToTalk) { shortcut in
                hotkeyManager.updateShortcutSummary(shortcut)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(
                    hotkeyManager.hasConfiguredShortcut
                        ? "Hold \(hotkeyManager.shortcutSummary) in any app to record, then release to transcribe."
                        : "Set a standard key combination to enable global push-to-talk."
                )
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(CueTheme.slate)

                Text("Bare Fn/Globe is not supported by the current global hotkey API, so use a normal shortcut chord.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(CueTheme.muted)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcript")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(CueTheme.ink)

            ScrollView {
                Text(model.transcript.isEmpty ? "Your transcript will appear here after you stop recording." : model.transcript)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .foregroundStyle(model.transcript.isEmpty ? CueTheme.slate : CueTheme.ink)
                    .padding(.top, 2)
            }
            .frame(minHeight: 180)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var insertionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last Insertion")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(CueTheme.ink)

            if let insertionResult = model.lastInsertionResult {
                HStack {
                    statusTile(title: "Delivery", value: insertionResult.delivery.title)

                    if let targetAppName = insertionResult.targetAppName {
                        statusTile(
                            title: insertionResult.delivery.usedAutomaticPaste ? "Target App" : "Frontmost App",
                            value: targetAppName
                        )
                    }
                }

                Text(insertionResult.delivery.detail)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(CueTheme.slate)

                if let bundleIdentifier = insertionResult.targetBundleIdentifier {
                    Text(bundleIdentifier)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(CueTheme.muted)
                        .textSelection(.enabled)
                }
            } else {
                Text("Finish a push-to-talk pass to see whether Cue sent the paste command or left the transcript on the clipboard.")
                    .foregroundStyle(CueTheme.slate)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var metricsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Latency")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(CueTheme.ink)

            if let metrics = model.latencyMetrics {
                HStack {
                    metricTile(title: "Record", value: metrics.recordingDuration.formattedSeconds)
                    metricTile(title: "Transcribe", value: metrics.transcriptionDuration.formattedSeconds)
                    metricTile(title: "Paste", value: metrics.pasteDuration.formattedSeconds)
                    metricTile(title: "Total", value: metrics.totalDuration.formattedSeconds)
                }

                HStack {
                    metricTile(title: "Model Load", value: metrics.modelLoadDuration.formattedSeconds)
                    metricTile(title: "Backend", value: metrics.backendPipelineDuration.formattedSeconds)
                }
            } else {
                Text("Run a short utterance to populate latency metrics.")
                    .foregroundStyle(CueTheme.slate)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func errorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last Error")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(CueTheme.errorInk)

            Text(message)
                .foregroundStyle(CueTheme.errorText)
                .textSelection(.enabled)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.98, green: 0.91, blue: 0.90))
        )
    }

    private func automationWarningCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.permissionSnapshot.canAutoPaste ? "Automation Warning" : "Automatic Paste Off")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(CueTheme.warningInk)

            Text(message)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(CueTheme.warningText)

            if !model.permissionSnapshot.canAutoPaste {
                HStack(spacing: 10) {
                    prominentActionButton(.openAccessibilitySettings)
                    secondaryActionButton(.restartApplication)
                }

                if let accessibilityRestartMessage = model.accessibilityRestartMessage {
                    Text(accessibilityRestartMessage)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(CueTheme.warningTextMuted)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.99, green: 0.95, blue: 0.88))
        )
    }

    private var detailsFooter: some View {
        HStack(spacing: 12) {
            if presentation.shouldOfferModelRetry {
                prominentActionButton(.retryModelPreparation)
            }

            Text("Cue runs from the menu bar. Open this window when you want visibility into permissions, paste diagnostics, and timing.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(CueTheme.muted)
        }
    }

    private func statusTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(CueTheme.slate)

            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(CueTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(CueTheme.slate)

            Text(value)
                .font(.system(.body, design: .monospaced).weight(.medium))
                .foregroundStyle(CueTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func prominentActionButton(_ action: CueAppAction) -> some View {
        Button(action.title) {
            model.perform(action)
        }
        .buttonStyle(.borderedProminent)
        .tint(CueTheme.accent)
    }

    private func secondaryActionButton(_ action: CueAppAction) -> some View {
        Button(action.title) {
            model.perform(action)
        }
        .buttonStyle(.bordered)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(CueTheme.cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.96), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 12)
    }
}
