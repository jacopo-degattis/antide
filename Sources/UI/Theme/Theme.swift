import SwiftUI

public enum CodexTheme {
    // Backgrounds
    public static let background = Color(red: 13/255, green: 17/255, blue: 23/255)
    public static let secondaryBackground = Color(red: 22/255, green: 27/255, blue: 34/255)
    public static let surface = Color(red: 33/255, green: 38/255, blue: 45/255)
    public static let surfaceHighlight = Color(red: 48/255, green: 54/255, blue: 61/255)

    // Borders
    public static let border = Color(red: 48/255, green: 54/255, blue: 61/255).opacity(0.8)
    public static let subtleBorder = Color.white.opacity(0.08)

    // Text
    public static let primaryText = Color(red: 240/255, green: 246/255, blue: 252/255)
    public static let secondaryText = Color(red: 139/255, green: 148/255, blue: 158/255)
    public static let tertiaryText = Color(red: 110/255, green: 118/255, blue: 129/255)

    // Accents
    public static let accentBlue = Color(red: 88/255, green: 166/255, blue: 255/255)
    public static let accentCyan = Color(red: 56/255, green: 189/255, blue: 248/255)
    public static let accentGreen = Color(red: 63/255, green: 185/255, blue: 80/255)
    public static let accentAmber = Color(red: 210/255, green: 153/255, blue: 34/255)
    public static let accentPurple = Color(red: 163/255, green: 113/255, blue: 247/255)
    public static let accentRed = Color(red: 248/255, green: 81/255, blue: 73/255)

    // Thinking Gradient
    public static let thinkingGradient = LinearGradient(
        colors: [
            Color(red: 163/255, green: 113/255, blue: 247/255),
            Color(red: 88/255, green: 166/255, blue: 255/255),
            Color(red: 56/255, green: 189/255, blue: 248/255)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}
