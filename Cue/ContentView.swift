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

                    if model.shouldShowSetupExperience {
                        setupContent
                    } else {
                        diagnosticsContent
                    }
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
        model.shouldShowSetupExperience
            ? "Complete macOS permissions here before Cue starts listening and pasting into other apps."
            : "Menu bar push-to-talk prototype that transcribes locally, then pastes into the frontmost app."
    }

    private var setupContent: some View {
        Group {
            setupOverviewCard
            permissionCards

            if let errorMessage = model.errorMessage {
                errorCard(message: errorMessage)
            }

            setupControls
        }
    }

    private var setupOverviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Setup Required")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(ink)

            if model.hasLoadedPermissionSnapshot {
                Text(model.permissionSnapshot.setupSummary)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(slate)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(accent)

                    Text("Cue is checking the permissions it needs.")
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
            permissionCard(for: .microphone)
            permissionCard(for: .paste)
        }
    }

    private func permissionCard(for permission: CuePermissionKind) -> some View {
        let state = model.permissionSnapshot.state(for: permission)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(permission.title)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(ink)

                    Text(permission.requirementSummary)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(slate)
                }

                Spacer(minLength: 12)

                Text(state.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(state.isGranted ? success : warning)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill((state.isGranted ? success : warning).opacity(0.12))
                    )
            }

            Text(permission.systemSettingsPath)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(muted)

            permissionActions(for: permission, state: state)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    @ViewBuilder
    private func permissionActions(for permission: CuePermissionKind, state: CuePermissionState) -> some View {
        switch permission {
        case .microphone:
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
                Text("Cue can use the microphone when you hold the shortcut.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(muted)
            }

        case .paste:
            if state != .granted {
                HStack(spacing: 10) {
                    Button("Grant Accessibility Access") {
                        Task {
                            await model.requestPastePermission()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)

                    Button("Open Accessibility Settings") {
                        model.openAccessibilitySettings()
                    }
                    .buttonStyle(.bordered)
                }

                Text("After enabling Cue in Accessibility, relaunch Cue to let paste permissions take effect.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(muted)
            } else {
                Text("Cue can synthesize Command-V into the focused destination app.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(muted)
            }
        }
    }

    private var setupControls: some View {
        HStack(spacing: 12) {
            if model.shouldOfferPastePermissionRecovery {
                Button("Relaunch Cue") {
                    model.relaunchApplication()
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }

            Text("Cue stays inactive until both permissions are granted.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(muted)
        }
    }

    private var diagnosticsContent: some View {
        Group {
            statusCard
            shortcutCard
            transcriptCard
            insertionCard
            metricsCard

            if let errorMessage = model.errorMessage {
                errorCard(message: errorMessage)
            }

            diagnosticsControls
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                statusTile(title: "Phase", value: model.phase.title)
                statusTile(title: "Model", value: model.modelStatus.title)
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
                    statusTile(title: "Target App", value: insertionResult.targetAppName)
                }

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
                Text("Finish a successful push-to-talk pass to see where Cue pasted and whether the previous clipboard was restored.")
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

    private var diagnosticsControls: some View {
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

            if model.shouldOfferPastePermissionRecovery {
                Button("Relaunch Cue") {
                    model.relaunchApplication()
                }
                .buttonStyle(.bordered)
                .tint(accent)
            }

            Text("Cue runs from the menu bar. Open this window when you want visibility into state, paste diagnostics, and timing.")
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
