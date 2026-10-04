import SwiftUI

/// Minimal in-stream activity label: a soft breathing glow communicates that the
/// agent is working without adding a large expandable panel to the conversation.
public struct ThinkingView: View {
    let state: ThinkingState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glow = false

    public init(state: ThinkingState) {
        self.state = state
    }

    public var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(CodexTheme.accentBlue.opacity(state.isThinking ? (glow ? 0.36 : 0.12) : 0.10))
                    .frame(width: 15, height: 15)
                    .blur(radius: state.isThinking && glow ? 5 : 2)

                Image(systemName: "sparkle")
                    .font(.system(size: 11.5, weight: .semibold))       // Increased (was 10.5)
                    .foregroundStyle(state.isThinking ? CodexTheme.accentBlue : CodexTheme.tertiaryText)
            }

            Text(state.isThinking ? "Thinking" : "Thought")
                .font(.system(size: 13.5, weight: .medium))             // Increased (was 12.5)
                .foregroundStyle(state.isThinking ? CodexTheme.primaryText : CodexTheme.secondaryText)
                .shadow(
                    color: state.isThinking ? CodexTheme.accentBlue.opacity(glow ? 0.48 : 0.08) : .clear,
                    radius: glow ? 7 : 1
                )

            if state.isThinking {
                HStack(spacing: 3) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(CodexTheme.accentBlue.opacity(glow ? (0.85 - Double(index) * 0.18) : 0.28))
                            .frame(width: 3, height: 3)
                    }
                }
            } else if let duration = state.durationSeconds, duration > 0 {
                Text(String(format: "%.1fs", duration))
                    .font(.system(size: 11.5, design: .monospaced))      // Increased (was 10.5)
                    .foregroundStyle(CodexTheme.tertiaryText)
            }
        }
        .fixedSize()
        .padding(.vertical, 3)
        .onAppear(perform: startGlow)
        .onChange(of: state.isThinking) { _, isThinking in
            if isThinking { startGlow() } else { glow = false }
        }
    }

    private func startGlow() {
        guard state.isThinking, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
            glow = true
        }
    }
}
