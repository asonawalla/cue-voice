import AppKit
import Observation
import SwiftUI

struct CueRecordingPillPresentation: Equatable {
    enum Phase: Equatable {
        case compact
        case recording
        case transcribing
        case pasting
        case failed
    }

    let phase: Phase?
    let previewText: String?
    let isPreviewUnavailable: Bool

    init(isEnabled: Bool, state: CueAppState) {
        guard isEnabled,
              state.permissions.isFullyConfigured,
              state.modelStatus.isReady
        else {
            phase = nil
            previewText = nil
            isPreviewUnavailable = false
            return
        }

        switch state.session {
        case .recording:
            phase = .recording
            let trimmedPreview = state.recordingPreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
            previewText = trimmedPreview.isEmpty ? nil : trimmedPreview
            isPreviewUnavailable = state.isRecordingPreviewUnavailable
        case .transcribing:
            phase = .transcribing
            previewText = nil
            isPreviewUnavailable = false
        case .pasting:
            phase = .pasting
            previewText = nil
            isPreviewUnavailable = false
        case .idle:
            phase = .compact
            previewText = nil
            isPreviewUnavailable = false
        case .failed:
            phase = .failed
            previewText = nil
            isPreviewUnavailable = false
        }
    }
}

struct CueRecordingPillLayout {
    static func size(for phase: CueRecordingPillPresentation.Phase) -> NSSize {
        switch phase {
        case .compact:
            NSSize(width: 48, height: 18)
        case .recording:
            NSSize(width: 430, height: 68)
        case .transcribing:
            NSSize(width: 146, height: 34)
        case .pasting:
            NSSize(width: 112, height: 34)
        case .failed:
            NSSize(width: 138, height: 34)
        }
    }
}

struct CueRecordingPillPlacement: Codable, Equatable {
    let displayIdentifier: String
    let normalizedCenterX: Double
    let normalizedCenterY: Double

    var isValid: Bool {
        normalizedCenterX.isFinite
            && normalizedCenterY.isFinite
            && (0 ... 1).contains(normalizedCenterX)
            && (0 ... 1).contains(normalizedCenterY)
    }
}

struct CueRecordingPillDisplayGeometry: Equatable {
    let identifier: String
    let safeFrame: NSRect
}

enum CueRecordingPillPlacementResolver {
    static func defaultPlacement(
        on display: CueRecordingPillDisplayGeometry,
        pillSize: NSSize,
        topInset: CGFloat = 8
    ) -> CueRecordingPillPlacement {
        let center = NSPoint(
            x: display.safeFrame.midX,
            y: display.safeFrame.maxY - topInset - pillSize.height / 2
        )
        return placement(forCenter: center, on: display)
    }

    static func frame(
        for pillSize: NSSize,
        placement: CueRecordingPillPlacement,
        on display: CueRecordingPillDisplayGeometry
    ) -> NSRect {
        let center = NSPoint(
            x: display.safeFrame.minX + CGFloat(placement.normalizedCenterX) * display.safeFrame.width,
            y: display.safeFrame.minY + CGFloat(placement.normalizedCenterY) * display.safeFrame.height
        )
        let proposedFrame = NSRect(
            x: center.x - pillSize.width / 2,
            y: center.y - pillSize.height / 2,
            width: pillSize.width,
            height: pillSize.height
        )
        return clamped(proposedFrame, inside: display.safeFrame)
    }

    static func placement(
        for pillFrame: NSRect,
        on display: CueRecordingPillDisplayGeometry
    ) -> CueRecordingPillPlacement {
        placement(forCenter: NSPoint(x: pillFrame.midX, y: pillFrame.midY), on: display)
    }

    static func clamped(_ frame: NSRect, inside safeFrame: NSRect) -> NSRect {
        let maximumX = max(safeFrame.minX, safeFrame.maxX - frame.width)
        let maximumY = max(safeFrame.minY, safeFrame.maxY - frame.height)
        return NSRect(
            x: clamp(frame.minX, minimum: safeFrame.minX, maximum: maximumX),
            y: clamp(frame.minY, minimum: safeFrame.minY, maximum: maximumY),
            width: frame.width,
            height: frame.height
        )
    }

    static func display(
        containing pillFrame: NSRect,
        among displays: [CueRecordingPillDisplayGeometry]
    ) -> CueRecordingPillDisplayGeometry? {
        let center = NSPoint(x: pillFrame.midX, y: pillFrame.midY)
        if let containingDisplay = displays.first(where: { $0.safeFrame.contains(center) }) {
            return containingDisplay
        }

        return displays.max { lhs, rhs in
            intersectionArea(of: pillFrame, and: lhs.safeFrame)
                < intersectionArea(of: pillFrame, and: rhs.safeFrame)
        }
    }

    private static func placement(
        forCenter center: NSPoint,
        on display: CueRecordingPillDisplayGeometry
    ) -> CueRecordingPillPlacement {
        let normalizedX = display.safeFrame.width > 0
            ? Double((center.x - display.safeFrame.minX) / display.safeFrame.width)
            : 0.5
        let normalizedY = display.safeFrame.height > 0
            ? Double((center.y - display.safeFrame.minY) / display.safeFrame.height)
            : 0.5
        return CueRecordingPillPlacement(
            displayIdentifier: display.identifier,
            normalizedCenterX: clamp(normalizedX, minimum: 0, maximum: 1),
            normalizedCenterY: clamp(normalizedY, minimum: 0, maximum: 1)
        )
    }

    private static func intersectionArea(of lhs: NSRect, and rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else {
            return 0
        }
        return intersection.width * intersection.height
    }

    private static func clamp<T: Comparable>(_ value: T, minimum: T, maximum: T) -> T {
        min(max(value, minimum), maximum)
    }
}

@MainActor
final class CueRecordingPillController: NSObject, NSWindowDelegate {
    private let model: CueAppModel
    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private var panel: CueRecordingPillPanel?
    private var isStarted = false
    private var currentPhase: CueRecordingPillPresentation.Phase?
    private var preferredPlacement: CueRecordingPillPlacement?
    private var isApplyingFrame = false
    private var pendingPlacementSave: Task<Void, Never>?
    private var screenChangeObserver: NSObjectProtocol?

    init(
        model: CueAppModel,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.model = model
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        super.init()
    }

    func start() {
        guard !isStarted else {
            return
        }

        isStarted = true
        preferredPlacement = loadPlacement()
        screenChangeObserver = notificationCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenConfigurationChange()
            }
        }
        observePresentation()
    }

    private func observePresentation() {
        let presentation = withObservationTracking {
            CueRecordingPillPresentation(
                isEnabled: model.recordingPillEnabled,
                state: model.state
            )
        } onChange: { [weak self] in
            guard let controller = self else {
                return
            }

            Task { @MainActor [controller] in
                controller.observePresentation()
            }
        }

        apply(presentation)
    }

    private func apply(_ presentation: CueRecordingPillPresentation) {
        guard let phase = presentation.phase else {
            panel?.orderOut(nil)
            currentPhase = nil
            return
        }

        currentPhase = phase
        let panel = panel ?? makePanel(initialSize: CueRecordingPillLayout.size(for: phase))
        applyPlacement(to: panel, for: phase)

        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func makePanel(initialSize: NSSize) -> CueRecordingPillPanel {
        let panel = CueRecordingPillPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.delegate = self

        let hostingView = CueRecordingPillHostingView(
            rootView: CueRecordingPillObservedView(model: model)
        )
        hostingView.frame = NSRect(origin: .zero, size: initialSize)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        self.panel = panel
        return panel
    }

    private func applyPlacement(
        to panel: CueRecordingPillPanel,
        for phase: CueRecordingPillPresentation.Phase
    ) {
        let displays = displayPairs()
        guard let target = targetDisplay(in: displays, for: preferredPlacement) else {
            return
        }

        let size = CueRecordingPillLayout.size(for: phase)
        if preferredPlacement == nil {
            preferredPlacement = CueRecordingPillPlacementResolver.defaultPlacement(
                on: target.geometry,
                pillSize: size
            )
        }
        guard let preferredPlacement else {
            return
        }

        let frame = CueRecordingPillPlacementResolver.frame(
            for: size,
            placement: preferredPlacement,
            on: target.geometry
        )
        setFrame(frame, for: panel)
    }

    private func targetDisplay(
        in displays: [(screen: NSScreen, geometry: CueRecordingPillDisplayGeometry)],
        for placement: CueRecordingPillPlacement?
    ) -> (screen: NSScreen, geometry: CueRecordingPillDisplayGeometry)? {
        if let placement,
           let preferred = displays.first(where: { $0.geometry.identifier == placement.displayIdentifier })
        {
            return preferred
        }

        if placement == nil,
           let pointerDisplay = displays.first(where: { $0.screen.frame.contains(NSEvent.mouseLocation) })
        {
            return pointerDisplay
        }

        if let currentScreen = panel?.screen,
           let currentDisplay = displays.first(where: { $0.screen === currentScreen })
        {
            return currentDisplay
        }

        if let mainScreen = NSScreen.main,
           let mainDisplay = displays.first(where: { $0.screen === mainScreen })
        {
            return mainDisplay
        }

        return displays.first
    }

    private func handleScreenConfigurationChange() {
        guard let panel, let currentPhase else {
            return
        }
        applyPlacement(to: panel, for: currentPhase)
    }

    func windowDidMove(_ notification: Notification) {
        guard let movedPanel = notification.object as? CueRecordingPillPanel,
              movedPanel === panel,
              !isApplyingFrame,
              movedPanel.isVisible
        else {
            return
        }

        let geometries = displayPairs().map(\.geometry)
        if let geometry = CueRecordingPillPlacementResolver.display(
            containing: movedPanel.frame,
            among: geometries
        ) {
            // Keep the live anchor current throughout the drag so a phase
            // change cannot resize the pill around its previously saved spot.
            preferredPlacement = CueRecordingPillPlacementResolver.placement(
                for: movedPanel.frame,
                on: geometry
            )
        }

        pendingPlacementSave?.cancel()
        pendingPlacementSave = Task { @MainActor [weak self, weak movedPanel] in
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            guard let self, let movedPanel else {
                return
            }
            self.finishMoving(movedPanel)
        }
    }

    private func finishMoving(_ panel: CueRecordingPillPanel) {
        let displayPairs = displayPairs()
        let geometries = displayPairs.map(\.geometry)
        guard let geometry = CueRecordingPillPlacementResolver.display(
            containing: panel.frame,
            among: geometries
        ) else {
            return
        }

        let clampedFrame = CueRecordingPillPlacementResolver.clamped(
            panel.frame,
            inside: geometry.safeFrame
        )
        setFrame(clampedFrame, for: panel)
        let placement = CueRecordingPillPlacementResolver.placement(
            for: clampedFrame,
            on: geometry
        )
        preferredPlacement = placement
        savePlacement(placement)
    }

    private func setFrame(_ frame: NSRect, for panel: CueRecordingPillPanel) {
        isApplyingFrame = true
        panel.setFrame(frame, display: true)
        isApplyingFrame = false
    }

    private func loadPlacement() -> CueRecordingPillPlacement? {
        guard let data = defaults.data(forKey: CueAppConfiguration.recordingPillPlacementDefaultsKey),
              let placement = try? JSONDecoder().decode(CueRecordingPillPlacement.self, from: data),
              placement.isValid
        else {
            return nil
        }
        return placement
    }

    private func savePlacement(_ placement: CueRecordingPillPlacement) {
        guard let data = try? JSONEncoder().encode(placement) else {
            return
        }
        defaults.set(data, forKey: CueAppConfiguration.recordingPillPlacementDefaultsKey)
    }

    private func displayPairs() -> [(screen: NSScreen, geometry: CueRecordingPillDisplayGeometry)] {
        NSScreen.screens.map { screen in
            let safeTop = min(
                screen.visibleFrame.maxY,
                screen.frame.maxY - screen.safeAreaInsets.top
            )
            let safeFrame = NSRect(
                x: screen.visibleFrame.minX,
                y: screen.visibleFrame.minY,
                width: screen.visibleFrame.width,
                height: max(0, safeTop - screen.visibleFrame.minY)
            )
            return (
                screen,
                CueRecordingPillDisplayGeometry(
                    identifier: displayIdentifier(for: screen),
                    safeFrame: safeFrame
                )
            )
        }
    }

    private func displayIdentifier(for screen: NSScreen) -> String {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screenNumber = screen.deviceDescription[screenNumberKey] as? NSNumber else {
            return "screen-\(screen.frame.origin.x)-\(screen.frame.origin.y)"
        }

        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        guard let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            return "display-\(displayID)"
        }
        let uuid = unmanagedUUID.takeRetainedValue()
        return CFUUIDCreateString(kCFAllocatorDefault, uuid) as String
    }
}

private final class CueRecordingPillPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class CueRecordingPillHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }
}

private struct CueRecordingPillObservedView: View {
    @Bindable var model: CueAppModel

    var body: some View {
        CueRecordingPillView(
            presentation: CueRecordingPillPresentation(
                isEnabled: model.recordingPillEnabled,
                state: model.state
            )
        )
    }
}

struct CueRecordingPillView: View {
    let presentation: CueRecordingPillPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let size = presentation.phase.map { CueRecordingPillLayout.size(for: $0) } ?? .zero

        ZStack {
            if let phase = presentation.phase {
                pill(for: phase)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: presentation.phase)
    }

    @ViewBuilder
    private func pill(for phase: CueRecordingPillPresentation.Phase) -> some View {
        switch phase {
        case .compact:
            compactPill
        case .recording:
            recordingPill
        case .transcribing:
            statusPill(
                phase: phase,
                label: "Transcribing",
                symbol: "waveform.badge.magnifyingglass"
            )
        case .pasting:
            statusPill(phase: phase, label: "Pasting", symbol: "arrow.down.doc.fill")
        case .failed:
            statusPill(
                phase: phase,
                label: "Dictation failed",
                symbol: "exclamationmark.triangle.fill",
                tint: .red,
                showsProgress: false,
                accessibilityLabel: "Cue dictation failed"
            )
        }
    }

    private var compactPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(CueTheme.accent)
                .frame(width: 5, height: 5)

            Image(systemName: "waveform")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
        }
        .frame(width: 48, height: 18)
        .cuePillSurface(cornerRadius: 9)
        .accessibilityLabel("Cue floating dictation preview")
    }

    private var recordingPill: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.red.opacity(0.18))
                    .frame(width: 30, height: 30)

                Circle()
                    .fill(.red)
                    .frame(width: 9, height: 9)
                    .shadow(color: .red.opacity(0.7), radius: 5)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("LISTENING")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.55))

                Text(recordingStatusText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(
                        presentation.previewText == nil
                            ? .white.opacity(0.62)
                            : .white.opacity(0.96)
                    )
                    .lineLimit(2)
                    .truncationMode(.head)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: presentation.isPreviewUnavailable ? "exclamationmark.triangle.fill" : "waveform")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(presentation.isPreviewUnavailable ? .orange : CueTheme.accent)
                .symbolEffect(
                    .variableColor.iterative.reversing,
                    options: .repeating,
                    isActive: !reduceMotion && !presentation.isPreviewUnavailable
                )
        }
        .padding(.horizontal, 16)
        .frame(width: 430, height: 68)
        .cuePillSurface(cornerRadius: 34)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            recordingAccessibilityLabel
        )
    }

    private var recordingStatusText: String {
        if presentation.isPreviewUnavailable {
            return "Live preview unavailable"
        }

        return presentation.previewText ?? "Start speaking…"
    }

    private var recordingAccessibilityLabel: String {
        if presentation.isPreviewUnavailable {
            return "Cue is recording. Live preview unavailable"
        }

        return presentation.previewText.map { "Cue is recording. Rough transcript: \($0)" }
            ?? "Cue is recording"
    }

    private func statusPill(
        phase: CueRecordingPillPresentation.Phase,
        label: String,
        symbol: String,
        tint: Color = CueTheme.accent,
        showsProgress: Bool = true,
        accessibilityLabel: String? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)

            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))

            if showsProgress {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 14)
        .frame(
            width: CueRecordingPillLayout.size(for: phase).width,
            height: CueRecordingPillLayout.size(for: phase).height
        )
        .cuePillSurface(cornerRadius: 17)
        .accessibilityLabel(accessibilityLabel ?? "Cue is \(label.lowercased())")
    }
}

private extension View {
    func cuePillSurface(cornerRadius: CGFloat) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.black.opacity(0.9))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.34), radius: 11, y: 5)
        }
    }
}

#Preview("Recording pill") {
    VStack(spacing: 18) {
        CueRecordingPillView(
            presentation: CueRecordingPillPresentation.preview(phase: .compact)
        )
        CueRecordingPillView(
            presentation: CueRecordingPillPresentation.preview(
                phase: .recording,
                text: "This is the rough text Cue is hearing while I keep talking."
            )
        )
        CueRecordingPillView(
            presentation: CueRecordingPillPresentation.preview(phase: .transcribing)
        )
        CueRecordingPillView(
            presentation: CueRecordingPillPresentation.preview(phase: .failed)
        )
    }
    .padding(24)
    .background(Color.gray.opacity(0.35))
}

private extension CueRecordingPillPresentation {
    static func preview(phase: Phase, text: String? = nil) -> CueRecordingPillPresentation {
        var state = CueAppState(
            permissions: CuePermissionSnapshot(microphone: .granted, accessibility: .granted)
        )
        state.recordingPreviewText = text ?? ""

        switch phase {
        case .compact:
            state.session = .idle
        case .recording:
            state.session = .recording
        case .transcribing:
            state.session = .transcribing
        case .pasting:
            state.session = .pasting
        case .failed:
            state.session = .failed(.emptyTranscript)
        }

        return CueRecordingPillPresentation(isEnabled: true, state: state)
    }
}
