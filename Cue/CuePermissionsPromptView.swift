import SwiftUI

struct CuePermissionsPromptView: View {
    @Bindable var model: CueAppModel
    @Environment(\.dismiss) private var dismiss

    private let ink = Color(red: 0.12, green: 0.17, blue: 0.25)
    private let slate = Color(red: 0.34, green: 0.40, blue: 0.50)
    private let accent = Color(red: 0.16, green: 0.42, blue: 0.66)
    private let success = Color(red: 0.15, green: 0.45, blue: 0.27)
    private let warning = Color(red: 0.74, green: 0.29, blue: 0.08)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            statusSection
            microphoneSection
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Finish Setup")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(ink)

            Text("Cue needs microphone access to record. Accessibility is optional for automatic paste and takes effect after Cue restarts.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(slate)
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
                title: CuePermissionKind.paste.title,
                value: model.permissionSnapshot.paste.title,
                isPositive: model.permissionSnapshot.canAutoPaste
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sectionBackground)
    }

    private var microphoneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Microphone")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(ink)

            if model.permissionSnapshot.microphone == .notDetermined {
                Text("Grant microphone access first so Cue can start recording.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(slate)

                footerButton(title: "Grant Microphone Access") {
                    Task {
                        await model.requestMicrophonePermission()
                    }
                }
            } else if model.permissionSnapshot.microphone == .denied {
                Text("Microphone access is blocked. Open System Settings to allow Cue to record.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(slate)

                footerButton(title: "Open Microphone Settings") {
                    model.openMicrophoneSettings()
                }
            } else {
                Text("Microphone is ready. Cue can record on this launch.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(slate)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sectionBackground)
    }

    private var accessibilitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Automatic Paste")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(ink)

            if !model.permissionSnapshot.isMicrophoneReady {
                Text("Finish microphone setup first. Then you can optionally enable Accessibility for automatic paste.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(slate)
            } else if model.permissionSnapshot.canAutoPaste {
                Text("Accessibility is ready on this launch. Cue can paste automatically into the focused app.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(slate)
            } else {
                Text(model.accessibilityRestartMessage ?? "Open Accessibility settings, enable Cue, then restart the app to turn automatic paste on.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(slate)

                HStack(spacing: 10) {
                    footerButton(title: "Open Accessibility Settings") {
                        model.openAccessibilitySettings()
                    }

                    Button("Restart Cue") {
                        model.restartApplication()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Continue in Clipboard Mode") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(accent)
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
                .foregroundStyle(ink)

            Spacer(minLength: 12)

            Text(value)
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

    private func footerButton(title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .tint(accent)
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
