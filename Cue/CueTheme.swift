import SwiftUI

enum CueTheme {
    static let ink = Color(red: 0.12, green: 0.17, blue: 0.25)
    static let slate = Color(red: 0.34, green: 0.40, blue: 0.50)
    static let muted = Color(red: 0.47, green: 0.53, blue: 0.61)
    static let accent = Color(red: 0.16, green: 0.42, blue: 0.66)
    static let cardFill = Color(red: 0.98, green: 0.99, blue: 1.00)
    static let success = Color(red: 0.15, green: 0.45, blue: 0.27)
    static let warning = Color(red: 0.74, green: 0.29, blue: 0.08)
    static let errorInk = Color(red: 0.49, green: 0.16, blue: 0.15)
    static let errorText = Color(red: 0.37, green: 0.12, blue: 0.11)
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
}
