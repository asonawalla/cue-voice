import SwiftUI

enum CueTheme {
    static let ink = Color.primary
    static let slate = Color.secondary
    static let accent = Color(red: 0.16, green: 0.42, blue: 0.66)
    static let success = Color.green
    static let errorInk = Color.red
    static let errorText = Color.red.opacity(0.8)

    static let cardCornerRadius: CGFloat = 12
    static let errorCornerRadius: CGFloat = 8
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
    func popoverBackground() -> some View {
        self.background(.regularMaterial)
    }
}
