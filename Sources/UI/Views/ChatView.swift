import SwiftUI

public struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel

    public init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Navigation Bar
            topBar

            Divider().background(CodexTheme.border)

            if let authUrl = viewModel.activeAuthURL {
                authBanner(url: authUrl)
            }

            // Message Timeline
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 12) {
                        if let session = viewModel.activeSession {
                            if session.messages.isEmpty {
                                emptyStateView
                            } else {
                                ForEach(session.messages) { message in
                                    MessageRowView(message: message)
                                        .id(message.id)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 16)
                }
                .onChange(of: viewModel.activeSession?.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: viewModel.activeSession?.messages.last?.content) { _, _ in
                    // Streaming text can update dozens of times per second; avoid
                    // repeatedly restarting an animation for every token.
                    scrollToBottom(proxy: proxy, animated: false)
                }
                .onChange(of: viewModel.activeSession?.messages.last?.toolCalls.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }

            // Bottom Input Area
            InputBarView(viewModel: viewModel)
        }
        .background(CodexTheme.background)
    }

    // MARK: - Subviews

    private var topBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.activeSession?.title ?? "Antigravity Codex")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(CodexTheme.primaryText)
                    .lineLimit(1)

                if let path = viewModel.activeSession?.workspacePath {
                    Text(path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(CodexTheme.tertiaryText)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Mode & Model Indicators
            if let session = viewModel.activeSession {
                HStack(spacing: 6) {
                    Label(session.mode.title, systemImage: session.mode.systemSymbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(CodexTheme.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(CodexTheme.surfaceHighlight.opacity(0.5))
                        .cornerRadius(5)

                    Text(session.modelId)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(CodexTheme.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(CodexTheme.surfaceHighlight.opacity(0.5))
                        .cornerRadius(5)
                }
            }

            // Clear chat button
            Button {
                clearCurrentSessionMessages()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12))
                    .foregroundColor(CodexTheme.tertiaryText)
                    .padding(6)
                    .background(CodexTheme.surfaceHighlight.opacity(0.5))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help("Clear messages in current chat")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(CodexTheme.secondaryBackground.opacity(0.8))
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [CodexTheme.accentPurple.opacity(0.2), CodexTheme.accentBlue.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)

                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(CodexTheme.thinkingGradient)
            }

            VStack(spacing: 6) {
                Text("Antigravity Autonomous Agent")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(CodexTheme.primaryText)

                Text("Powered by refined-antigravity-acp and Google's agy CLI")
                    .font(.system(size: 12.5))
                    .foregroundColor(CodexTheme.secondaryText)
            }

            // Quick suggestion prompts
            VStack(spacing: 8) {
                suggestionButton(
                    title: "Inspect workspace status and agy CLI version",
                    icon: "terminal"
                )
                suggestionButton(
                    title: "Analyze project architecture and generate execution plan",
                    icon: "list.clipboard"
                )
                suggestionButton(
                    title: "Check git modified files and review pending changes",
                    icon: "doc.badge.gearshape"
                )
            }
            .frame(maxWidth: 420)
            .padding(.top, 8)

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 20)
    }

    private func authBanner(url: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .foregroundColor(CodexTheme.accentBlue)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text("Google Account Authentication Required")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(CodexTheme.primaryText)
                Text("The ACP server opened a browser page to sign in with Google.")
                    .font(.system(size: 11))
                    .foregroundColor(CodexTheme.secondaryText)
            }

            Spacer()

            Button(action: {
                #if canImport(AppKit)
                NSWorkspace.shared.open(url)
                #endif
            }) {
                Text("Open Sign-In Page")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(CodexTheme.accentBlue)
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Button(action: {
                viewModel.activeAuthURL = nil
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(CodexTheme.tertiaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(CodexTheme.accentBlue.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CodexTheme.accentBlue.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(8)
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private func suggestionButton(title: String, icon: String) -> some View {
        Button {
            viewModel.inputText = title
            viewModel.sendCurrentPrompt()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(CodexTheme.accentBlue)

                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundColor(CodexTheme.secondaryText)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
                    .foregroundColor(CodexTheme.tertiaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(CodexTheme.surface.opacity(0.7))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(CodexTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        guard let lastId = viewModel.activeSession?.messages.last?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }

    private func clearCurrentSessionMessages() {
        guard let sId = viewModel.selectedSessionId,
              let idx = viewModel.sessions.firstIndex(where: { $0.id == sId }) else { return }
        viewModel.sessions[idx].messages.removeAll()
    }
}
