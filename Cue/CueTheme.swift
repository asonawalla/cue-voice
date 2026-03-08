import SwiftUI

enum CueTheme {
    static let ink = Color.primary
    static let slate = Color.secondary
    static let muted = Color.secondary
    static let accent = Color(red: 0.16, green: 0.42, blue: 0.66)
    static let cardFill = Color(red: 0.98, green: 0.99, blue: 1.00)
    static let success = Color.green
    static let warning = Color(red: 0.74, green: 0.29, blue: 0.08)
    static let errorInk = Color.red
    static let errorText = Color.red.opacity(0.8)
    static let warningInk = Color(red: 0.49, green: 0.25, blue: 0.05)
    static let warningText = Color(red: 0.38, green: 0.22, blue: 0.07)
    static let warningTextMuted = Color(red: 0.45, green: 0.28, blue: 0.08)

    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.93, green: 0.95, blue: 0.98),
            Color(red: 0.84, green: 0.89, blue: 0.95)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardCornerRadius: CGFloat = 12
    static let errorCornerRadius: CGFloat = 8
    static let popoverPadding: CGFloat = 20
    static let cardPadding: CGFloat = 12
}

extension View {
    @ViewBuilder
    func glassCard(
        cornerRadius: CGFloat = CueTheme.cardCornerRadius,
        style: RoundedCornerStyle = .continuous
    ) -> some View {
        if #available(macOS 26.0, *) {
            self
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: style))
        } else {
            self
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: style)
                        .fill(.primary.opacity(0.08))
                        .background(.regularMaterial)
                )
        }
    }

    @ViewBuilder
    func glassCardTinted(
        tintColor: Color,
        cornerRadius: CGFloat = CueTheme.cardCornerRadius,
        style: RoundedCornerStyle = .continuous
    ) -> some View {
        if #available(macOS 26.0, *) {
            self
                .glassEffect(.regular.tint(tintColor), in: RoundedRectangle(cornerRadius: cornerRadius, style: style))
        } else {
            self
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: style)
                        .fill(tintColor.opacity(0.12))
                        .background(.regularMaterial)
                )
        }
    }

    @ViewBuilder
    func glassButton(interactive: Bool = true) -> some View {
        if #available(macOS 26.0, *) {
            if interactive {
                self.glassEffect(.regular.interactive(), in: .capsule)
            } else {
                self.glassEffect(.regular, in: .capsule)
            }
        } else {
            self
                .background(.regularMaterial, in: .capsule)
        }
    }

    @ViewBuilder
    func popoverBackground() -> some View {
        self.background(.regularMaterial)
    }
}
