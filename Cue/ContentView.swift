import KeyboardShortcuts
import SwiftUI

struct ContentView: View {
    @Bindable var model: CueAppModel
    @Bindable var hotkeyManager: CueHotkeyManager

    private let ink = Color(red: 0.12, green: 0.17, blue: 0.25)
    private let slate = Color(red: 0.34, green: 0.40, blue: 0.50)
    private let muted = Color(red: 0.47, green: 0.53, blue: 0.61)
    private let accent = Color(red: 0.16, green: 0.42, blue: 0.66)
    private let cardFill = Color(red: 0.98, green: 0.99, blue: 1.00)
    private let success = Color(red: 0.15, green: 0.45, blue: 0.27)
    private let warning = Color(red: 0.74, green: 0.29, blue: 0.08)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.93, green: 0.95, blue: 0.98),
                    Color(red: 0.84, green: 0.89, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cue")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(ink)

            Text(headerSubtitle)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(slate)
        }
    }

    private var headerSubtitle: String {
        "Menu bar push-to-talk prototype with a debug window for permissions, transcript delivery, and timing details."
    }

    private var permissionsOverviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Permissions")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(ink)

            if model.hasLoadedPermissionSnapshot {
                Text(model.permissionSnapshot.setupSummary)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(slate)

                Text("Cue checks permissions at launch. Microphone is required for dictation, and Accessibility is optional for automatic paste after Cue restarts.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(muted)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(accent)

                    Text("Cue is checking the current permission state.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(slate)
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

        return VStack(alignment: .leading, spacing: 14) {
            cardHeader(
                title: CuePermissionKind.microphone.title,
                summary: CuePermissionKind.microphone.requirementSummary,
                statusTitle: state.title,
                isPositive: state.isGranted
            )

            Text(CuePermissionKind.microphone.systemSettingsPath)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(muted)

            if state == .notDetermined {
                Button("Grant Microphone Access") {
                    Task {
                        await model.requestMicrophonePermission()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            } else if state == .denied {
                Button("Open Microphone Settings") {
                    model.openMicrophoneSettings()
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            } else {
                Text("Cue can start recording when you hold the shortcut.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(muted)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var accessibilityCard: some View {
        let state = model.permissionSnapshot.paste

        return VStack(alignment: .leading, spacing: 14) {
            cardHeader(
                title: CuePermissionKind.paste.title,
                summary: CuePermissionKind.paste.requirementSummary,
                statusTitle: state.title,
                isPositive: state.isAvailable
            )

            Text(CuePermissionKind.paste.systemSettingsPath)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(muted)

            if !model.permissionSnapshot.isMicrophoneReady {
                Text("Finish microphone setup first. Then you can optionally enable Accessibility for automatic paste.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(muted)
            } else if !state.isAvailable {
                HStack(spacing: 10) {
                    Button("Open Accessibility Settings") {
                        model.openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)

                    Button("Restart Cue") {
                        model.restartApplication()
                    }
                    .buttonStyle(.bordered)
                }

                Text(model.accessibilityRestartMessage ?? "Cue still works without this. Until Accessibility is enabled and Cue restarts, transcripts stay on the clipboard for manual paste.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(muted)
            } else {
                Text("Cue can synthesize Command-V into the focused destination app.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(muted)
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
                    .foregroundStyle(ink)

                Text(summary)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(slate)
            }

            Spacer(minLength: 12)

            Text(statusTitle)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(isPositive ? success : warning)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill((isPositive ? success : warning).opacity(0.12))
                )
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Status")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(ink)

            HStack {
                statusTile(title: "Phase", value: model.phase.title)
                statusTile(title: "Model", value: model.modelStatus.title)
                statusTile(title: "Auto Paste", value: model.permissionSnapshot.paste.title)
            }

            if let progressValue = model.modelStatus.progressValue {
                ProgressView(value: progressValue)
                    .tint(accent)
            } else if model.isModelPreparing {
                ProgressView()
                    .controlSize(.small)
                    .tint(accent)
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
                .foregroundStyle(ink)

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
                .foregroundStyle(slate)

                Text("Bare Fn/Globe is not supported by the current global hotkey API, so use a normal shortcut chord.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(muted)
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
                .foregroundStyle(ink)

            ScrollView {
                Text(model.transcript.isEmpty ? "Your transcript will appear here after you stop recording." : model.transcript)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .foregroundStyle(model.transcript.isEmpty ? slate : ink)
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
                .foregroundStyle(ink)

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
                    .foregroundStyle(slate)

                Text(insertionResult.clipboardRestoreOutcome.title)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(slate)

                if let bundleIdentifier = insertionResult.targetBundleIdentifier {
                    Text(bundleIdentifier)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(muted)
                        .textSelection(.enabled)
                }
            } else {
                Text("Finish a push-to-talk pass to see whether Cue sent the paste command or left the transcript on the clipboard.")
                    .foregroundStyle(slate)
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
                .foregroundStyle(ink)

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
                    .foregroundStyle(slate)
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
                .foregroundStyle(Color(red: 0.49, green: 0.16, blue: 0.15))

            Text(message)
                .foregroundStyle(Color(red: 0.37, green: 0.12, blue: 0.11))
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
                .foregroundStyle(Color(red: 0.49, green: 0.25, blue: 0.05))

            Text(message)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color(red: 0.38, green: 0.22, blue: 0.07))

            if !model.permissionSnapshot.canAutoPaste {
                HStack(spacing: 10) {
                    Button("Open Accessibility Settings") {
                        model.openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)

                    Button("Restart Cue") {
                        model.restartApplication()
                    }
                    .buttonStyle(.bordered)
                }

                if let accessibilityRestartMessage = model.accessibilityRestartMessage {
                    Text(accessibilityRestartMessage)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color(red: 0.45, green: 0.28, blue: 0.08))
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
            if model.shouldOfferModelRetry {
                Button("Retry Model Preparation") {
                    Task {
                        await model.retryModelPreparation()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }

            Text("Cue runs from the menu bar. Open this window when you want visibility into permissions, paste diagnostics, and timing.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(muted)
        }
    }

    private func statusTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(slate)

            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(slate)

            Text(value)
                .font(.system(.body, design: .monospaced).weight(.medium))
                .foregroundStyle(ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.96), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 12)
    }
}
