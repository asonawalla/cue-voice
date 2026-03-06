import SwiftUI

struct ContentView: View {
    @Bindable var model: CueAppModel
    
    private let ink = Color(red: 0.12, green: 0.17, blue: 0.25)
    private let slate = Color(red: 0.34, green: 0.40, blue: 0.50)
    private let muted = Color(red: 0.47, green: 0.53, blue: 0.61)
    private let accent = Color(red: 0.16, green: 0.42, blue: 0.66)
    private let cardFill = Color(red: 0.98, green: 0.99, blue: 1.00)

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

            VStack(alignment: .leading, spacing: 20) {
                header
                statusCard
                transcriptCard
                metricsCard

                if let errorMessage = model.errorMessage {
                    errorCard(message: errorMessage)
                }

                controls
            }
            .padding(28)
        }
        .task {
            await model.bootstrap()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cue")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(ink)

            Text("Local speech-to-text spike for the base.en WhisperKit model.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(slate)
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
            } else if model.phase == .preparingModel {
                ProgressView()
                    .controlSize(.small)
                    .tint(accent)
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

    private var metricsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Latency")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(ink)

            if let metrics = model.latencyMetrics {
                HStack {
                    metricTile(title: "Record", value: metrics.recordingDuration.formattedSeconds)
                    metricTile(title: "Transcribe", value: metrics.transcriptionDuration.formattedSeconds)
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

    private var controls: some View {
        HStack(spacing: 12) {
            Button(model.primaryButtonTitle) {
                Task {
                    await model.handlePrimaryAction()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(model.primaryButtonDisabled)

            Text("Click Stop Recording when you're done.")
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
