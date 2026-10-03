import SwiftUI

public struct ThinkingView: View {
    let state: ThinkingState
    @State private var isExpanded: Bool = false
    @State private var timerElapsed: Double = 0.0
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    public init(state: ThinkingState) {
        self.state = state
        self._isExpanded = State(initialValue: state.isThinking)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Toggle
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    // Icon
                    ZStack {
                        if state.isThinking {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(CodexTheme.thinkingGradient)
                                .shimmering()
                        } else {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(CodexTheme.accentPurple)
                        }
                    }

                    // Title
                    if state.isThinking {
                        Text("Thinking...")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CodexTheme.thinkingGradient)
                            .shimmering()
                    } else {
                        Text("Thought Process")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(CodexTheme.secondaryText)
                    }

                    Spacer()

                    // Metrics (Elapsed time / tokens)
                    HStack(spacing: 8) {
                        if let dur = displayDuration {
                            HStack(spacing: 3) {
                                Image(systemName: "stopwatch")
                                    .font(.system(size: 10))
                                Text(String(format: "%.1fs", dur))
                                    .font(.system(size: 11, design: .monospaced))
                            }
                            .foregroundColor(CodexTheme.tertiaryText)
                        }

                        if let tokens = state.tokenCount, tokens > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "number")
                                    .font(.system(size: 10))
                                Text("\(tokens) tokens")
                                    .font(.system(size: 11, design: .monospaced))
                            }
                            .foregroundColor(CodexTheme.tertiaryText)
                        }

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(CodexTheme.tertiaryText)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(CodexTheme.surface.opacity(0.85))
            }
            .buttonStyle(.plain)

            // Expandable Content
            if isExpanded {
                Divider().background(CodexTheme.border)

                VStack(alignment: .leading, spacing: 6) {
                    if state.content.isEmpty {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Formulating reasoning steps...")
                                .font(.system(size: 12))
                                .italic()
                                .foregroundColor(CodexTheme.secondaryText)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            Text(state.content)
                                .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                                .foregroundColor(CodexTheme.secondaryText)
                                .lineSpacing(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 220)
                    }
                }
                .padding(12)
                .background(CodexTheme.secondaryBackground.opacity(0.95))
            }
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    state.isThinking
                        ? CodexTheme.accentPurple.opacity(0.4)
                        : CodexTheme.border,
                    lineWidth: 1
                )
        )
        .onReceive(timer) { _ in
            if state.isThinking, let start = state.startTime {
                timerElapsed = Date().timeIntervalSince(start)
            }
        }
        .onChange(of: state.isThinking) { _, newValue in
            if newValue {
                withAnimation {
                    isExpanded = true
                }
            }
        }
    }

    private var displayDuration: Double? {
        if state.isThinking {
            return timerElapsed > 0 ? timerElapsed : nil
        }
        return state.durationSeconds
    }
}
