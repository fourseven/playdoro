import SwiftUI

enum Theme {
    static let background = Color(red: 0.04, green: 0.04, blue: 0.06)
    static let surface = Color(red: 0.12, green: 0.12, blue: 0.16)
    static let surfaceElevated = Color(red: 0.18, green: 0.18, blue: 0.24)

    static let accentGradient = LinearGradient(
        colors: [
            Color(red: 0.62, green: 0.32, blue: 0.96),
            Color(red: 0.95, green: 0.31, blue: 0.66)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accent = Color(red: 0.82, green: 0.45, blue: 0.92)

    /// Full-screen gradient used behind the connect-flow views (disconnected,
    /// linking, discovering, failed). Subtle purple tint fading to the base
    /// so the flow feels cohesive as state changes.
    static let connectBackdrop = LinearGradient(
        colors: [
            Color(red: 0.12, green: 0.08, blue: 0.18),
            Theme.background
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let timerFont = Font.system(size: 76, weight: .heavy, design: .rounded)
    static let titleFont = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let trackTitleFont = Font.system(.title3, design: .rounded).weight(.semibold)
    static let monoDigit = Font.system(.body, design: .monospaced)
}
