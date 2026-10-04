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
            VStack(alignment: .leading, spacing: 6) {
                // Show attached files as chips
                if !message.attachments.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(message.attachments) { attach in
                            attachmentChip(attach)
                        }
                    }
                }

                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.system(size: 15))                                    // Increased (was 14)
                        .foregroundStyle(CodexTheme.primaryText)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background(CodexTheme.surfaceHighlight.opacity(0.72), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }

    /// Displays an attached file as a compact chip in the user message bubble.
    private func attachmentChip(_ attach: FileAttachment) -> some View {
        HStack(spacing: 8) {
            Image(systemName: attach.iconName)
                .font(.system(size: 12))
                .foregroundStyle(CodexTheme.secondaryText)

            VStack(alignment: .leading, spacing: 2) {
                Text(attach.fileName)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(CodexTheme.primaryText)
                    .lineLimit(1)
                Text(attach.formattedSize)
                    .font(.system(size: 11))
                    .foregroundStyle(CodexTheme.tertiaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(CodexTheme.surface.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
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
