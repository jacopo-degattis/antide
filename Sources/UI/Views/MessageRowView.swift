import AppKit
import SwiftUI

public struct MessageRowView: View {
    let message: ChatMessage
    let onPermissionSelect: (PendingACPApproval, String) -> Void
    @State private var copied = false

    public init(
        message: ChatMessage,
        onPermissionSelect: @escaping (PendingACPApproval, String) -> Void = { _, _ in }
    ) {
        self.message = message
        self.onPermissionSelect = onPermissionSelect
    }

    public var body: some View {
        Group {
            if message.role == .user {
                userMessage
            } else {
                assistantMessage
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, message.role == .user ? 2 : 1)
    }

    private var userMessage: some View {
        HStack {
            Spacer(minLength: 48)
            Text(message.content)
                .font(.system(size: 14))
                .foregroundStyle(CodexTheme.primaryText)
                .lineSpacing(4)
                .textSelection(.enabled)
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .background(CodexTheme.surfaceHighlight.opacity(0.72), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }

    private var assistantMessage: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let thinking = message.thinkingState, thinking.isThinking || !thinking.content.isEmpty {
                ThinkingView(state: thinking)
            }

            if !message.planSteps.isEmpty {
                PlanTimelineView(steps: message.planSteps)
            }

            if !message.toolCalls.isEmpty {
                VStack(spacing: 8) {
                    ForEach(message.toolCalls) { toolCall in
                        ToolCallCardView(item: toolCall)
                    }
                }
            }

            if let approval = message.pendingApproval {
                PermissionRequestCardView(request: approval) { optionId in
                    onPermissionSelect(approval, optionId)
                }
            }

            if !message.content.isEmpty {
                MarkdownMessageView(markdown: message.content)
            } else if message.isStreaming && message.thinkingState?.isThinking != true && message.toolCalls.isEmpty {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small).tint(CodexTheme.secondaryText)
                    Text("Working")
                        .font(.system(size: 12))
                        .foregroundStyle(CodexTheme.tertiaryText)
                }
            }

            if !message.isStreaming && !message.content.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 10))
                        .foregroundStyle(CodexTheme.tertiaryText)
                    Text("Antigravity")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(CodexTheme.tertiaryText)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.content, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10.5))
                            .foregroundStyle(CodexTheme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Copy response")
                }
                .padding(.top, -4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
