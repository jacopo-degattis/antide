import AppKit
import SwiftUI

public struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel

    public init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let session = viewModel.activeSession, !session.messages.isEmpty {
                conversationHeader(session)
            } else {
                Spacer().frame(height: 8)
            }

            if let authUrl = viewModel.activeAuthURL {
                authBanner(url: authUrl)
                    .padding(.horizontal, 26)
                    .padding(.top, 8)
            }

            if case .error(let message) = viewModel.connectionStatus {
                connectionNotice(message)
                    .padding(.horizontal, 26)
                    .padding(.top, 8)
            }

            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        if let session = viewModel.activeSession {
                            if session.messages.isEmpty {
                                emptyState
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: geometry.size.height)
                            } else {
                                LazyVStack(spacing: 24) {
                                    ForEach(session.messages) { message in
                                        MessageRowView(message: message) { approval, optionId in
                                            viewModel.respondToPermission(approval, optionId: optionId)
                                        }
                                            .frame(maxWidth: 790)
                                            .frame(maxWidth: .infinity)
                                            .id(message.id)
                                    }
                                }
                                .padding(.top, 24)
                                .padding(.bottom, 28)
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .onChange(of: viewModel.activeSession?.messages.count) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: viewModel.activeSession?.messages.last?.content) { _, _ in
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                    .onChange(of: viewModel.activeSession?.messages.last?.toolCalls.count) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                }
            }

            InputBarView(viewModel: viewModel)
        }
        .background(CodexTheme.background.ignoresSafeArea())
    }

    private func conversationHeader(_ session: ChatSession) -> some View {
        HStack(spacing: 9) {
            Text(session.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CodexTheme.primaryText)
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(CodexTheme.tertiaryText)

            Spacer()

            Text(session.workspacePath.isEmpty ? "General chat" : URL(fileURLWithPath: session.workspacePath).lastPathComponent)
                .font(.system(size: 11.5))
                .foregroundStyle(CodexTheme.secondaryText)
                .lineLimit(1)

            Button {
                clearCurrentSessionMessages()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(CodexTheme.secondaryText)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Clear conversation")
        }
        .padding(.horizontal, 25)
        .frame(height: 42)
        .overlay(alignment: .bottom) { Rectangle().fill(CodexTheme.border).frame(height: 1) }
    }

    private var emptyState: some View {
        VStack(spacing: 19) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(CodexTheme.tertiaryText)
                .frame(width: 54, height: 54)
                .overlay(Circle().strokeBorder(CodexTheme.border, lineWidth: 1))

            HStack(spacing: 5) {
                if hasTargetWorkspace {
                    Text("What should we build in")
                        .foregroundStyle(CodexTheme.primaryText)
                    Button(workspaceName) {
                        chooseWorkspace()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(CodexTheme.primaryText)
                    .underline(true, color: CodexTheme.tertiaryText)
                    .help("Choose a project workspace")
                    Text("?")
                        .foregroundStyle(CodexTheme.primaryText)
                } else {
                    Text("What can I help you with?")
                        .foregroundStyle(CodexTheme.primaryText)
                }
            }
            .font(.system(size: 25, weight: .regular))
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .offset(y: -24)
        .animation(.easeOut(duration: 0.22), value: workspaceName)
    }

    private func authBanner(url: URL) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .foregroundStyle(CodexTheme.accentAmber)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sign in to Antigravity")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CodexTheme.primaryText)
                Text("The ACP server requires Google account authentication.")
                    .font(.system(size: 11))
                    .foregroundStyle(CodexTheme.secondaryText)
            }
            Spacer()
            Button("Open sign-in") { NSWorkspace.shared.open(url) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button {
                viewModel.activeAuthURL = nil
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(CodexTheme.tertiaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(11)
        .background(CodexTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(CodexTheme.border))
    }

    private func connectionNotice(_ message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(CodexTheme.accentAmber)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(CodexTheme.secondaryText)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("Reconnect") { Task { await viewModel.reconnect() } }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(CodexTheme.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
    }

    private var hasTargetWorkspace: Bool {
        guard let path = viewModel.activeSession?.workspacePath else { return false }
        return !path.isEmpty
    }

    private var workspaceName: String {
        guard let path = viewModel.activeSession?.workspacePath, !path.isEmpty else { return "General chat" }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? "Workspace" : name
    }

    private func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url,
           let id = viewModel.selectedSessionId {
            let workspace = viewModel.addWorkspace(at: url.path)
            viewModel.moveSession(id, toWorkspacePath: workspace.path)
        }
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
        guard let id = viewModel.selectedSessionId,
              let index = viewModel.sessions.firstIndex(where: { $0.id == id }) else { return }
        viewModel.sessions[index].messages.removeAll()
    }
}
