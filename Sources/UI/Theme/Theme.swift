import SwiftUI

/// Neutral graphite palette modeled after Codex for macOS, with restrained blue
/// accents for selection and primary actions.
public enum CodexTheme {
    public static let background = Color(red: 24 / 255, green: 24 / 255, blue: 24 / 255)
    public static let secondaryBackground = Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255)
    public static let surface = Color(red: 39 / 255, green: 39 / 255, blue: 39 / 255)
    public static let surfaceHighlight = Color(red: 53 / 255, green: 53 / 255, blue: 53 / 255)

    public static let border = Color.white.opacity(0.085)
    public static let subtleBorder = Color.white.opacity(0.055)

    public static let primaryText = Color(red: 242 / 255, green: 242 / 255, blue: 242 / 255)
    public static let secondaryText = Color(red: 180 / 255, green: 180 / 255, blue: 180 / 255)
    public static let tertiaryText = Color(red: 126 / 255, green: 126 / 255, blue: 126 / 255)

    public static let accentBlue = Color(red: 76 / 255, green: 121 / 255, blue: 211 / 255)
    public static let accentCyan = Color(red: 105 / 255, green: 164 / 255, blue: 194 / 255)
    public static let accentGreen = Color(red: 95 / 255, green: 165 / 255, blue: 119 / 255)
    public static let accentAmber = Color(red: 199 / 255, green: 157 / 255, blue: 83 / 255)
    public static let accentPurple = Color(red: 155 / 255, green: 139 / 255, blue: 190 / 255)
    public static let accentRed = Color(red: 201 / 255, green: 102 / 255, blue: 96 / 255)

    public static let thinkingGradient = LinearGradient(
        colors: [accentPurple, accentBlue, accentCyan],
        startPoint: .leading,
        endPoint: .trailing
    )
}
