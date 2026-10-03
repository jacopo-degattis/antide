import SwiftUI

public struct MessageRowView: View {
    let message: ChatMessage

    public init(message: ChatMessage) {
        self.message = message
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            avatarView

            // Content Column
            VStack(alignment: .leading, spacing: 10) {
                // Header (Name & Time)
                HStack(spacing: 8) {
                    Text(message.role == .user ? "You" : "Antigravity")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(CodexTheme.primaryText)

                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 11))
                        .foregroundColor(CodexTheme.tertiaryText)

                    if message.isStreaming {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.5)
                            Text("Active")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(CodexTheme.accentCyan)
                        }
                    }

                    Spacer()
                }

                // User Content
                if message.role == .user {
                    Text(message.content)
                        .font(.system(size: 13.5))
                        .foregroundColor(CodexTheme.primaryText)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }

                // Assistant Content
                if message.role == .assistant {
                    // 1. Thinking Drawer
                    if let thinking = message.thinkingState, thinking.isThinking || !thinking.content.isEmpty {
                        ThinkingView(state: thinking)
                    }

                    // 2. Plan Timeline
                    if !message.planSteps.isEmpty {
                        PlanTimelineView(steps: message.planSteps)
                    }

                    // 3. Tool Calls
                    if !message.toolCalls.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(message.toolCalls) { toolCall in
                                ToolCallCardView(item: toolCall)
                            }
                        }
                    }

                    // 4. Text Response Content
                    if !message.content.isEmpty {
                        Text(message.content)
                            .font(.system(size: 13.5))
                            .foregroundColor(CodexTheme.primaryText)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    } else if message.isStreaming && (message.thinkingState?.isThinking != true) && message.toolCalls.isEmpty {
                        HStack(spacing: 4) {
                            Circle().fill(CodexTheme.accentBlue).frame(width: 5, height: 5)
                            Circle().fill(CodexTheme.accentBlue).frame(width: 5, height: 5).opacity(0.6)
                            Circle().fill(CodexTheme.accentBlue).frame(width: 5, height: 5).opacity(0.3)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            message.role == .user
                ? CodexTheme.surface.opacity(0.3)
                : Color.clear
        )
        .cornerRadius(8)
    }

    @ViewBuilder
    private var avatarView: some View {
        if message.role == .user {
            ZStack {
                Circle()
                    .fill(CodexTheme.surfaceHighlight)
                    .frame(width: 28, height: 28)

                Image(systemName: "person.fill")
                    .font(.system(size: 13))
                    .foregroundColor(CodexTheme.secondaryText)
            }
        } else {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [CodexTheme.accentPurple, CodexTheme.accentBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)

                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }
}
