import AppKit
import SwiftUI

public struct SidebarView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var expandedWorkspaceIDs: Set<UUID> = []

    public init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            if isSearchPresented { searchField }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 23) {
                    projectsSection
                    generalChatsSection
                }
                .padding(.horizontal, 11)
                .padding(.top, 17)
                .padding(.bottom, 18)
            }

            Spacer(minLength: 0)
            sidebarFooter
        }
        .frame(width: 282)
        .background(CodexTheme.secondaryBackground)
        .overlay(alignment: .trailing) {
            Rectangle().fill(CodexTheme.border).frame(width: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Antide")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CodexTheme.primaryText)

            Spacer()

            Button {
                isSearchPresented.toggle()
                if !isSearchPresented { searchText = "" }
            } label: {
                Image(systemName: isSearchPresented ? "xmark" : "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(CodexTheme.secondaryText)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Search chats and projects")

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(CodexTheme.secondaryText)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")

            Button {
                Task { await viewModel.reconnect() }
            } label: {
                connectionIndicator.frame(width: 26, height: 28)
            }
            .buttonStyle(.plain)
            .help(viewModel.connectionStatus.displayText + " — click to reconnect")
        }
        .padding(.horizontal, 15)
        .frame(height: 54)
        .overlay(alignment: .bottom) { Rectangle().fill(CodexTheme.border).frame(height: 1) }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(CodexTheme.tertiaryText)
            TextField("Search chats and projects", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CodexTheme.surface, in: RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionHeading("Projects", symbol: "plus", help: "Add a workspace folder") {
                addProjectFolder()
            }

            if filteredWorkspaces.isEmpty {
                Button(action: addProjectFolder) {
                    Label("Add a workspace folder", systemImage: "folder.badge.plus")
                        .font(.system(size: 12))
                        .foregroundStyle(CodexTheme.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
            } else {
                ForEach(filteredWorkspaces) { workspace in
                    workspaceRow(workspace)
                }
            }
        }
    }

    private func workspaceRow(_ workspace: Workspace) -> some View {
        let isExpanded = expandedWorkspaceIDs.contains(workspace.id)

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if isExpanded {
                            expandedWorkspaceIDs.remove(workspace.id)
                        } else {
                            expandedWorkspaceIDs.insert(workspace.id)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(CodexTheme.tertiaryText)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        Image(systemName: "folder")
                            .font(.system(size: 13))
                            .foregroundStyle(CodexTheme.secondaryText)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workspace.name)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(CodexTheme.primaryText)
                                .lineLimit(1)
                            Text(workspace.path)
                                .font(.system(size: 10))
                                .foregroundStyle(CodexTheme.tertiaryText)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 5)
                    .padding(.vertical, 8)
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help("Show chats in \(workspace.name)")

                Button {
                    viewModel.newSession(inWorkspacePath: workspace.path)
                    expandedWorkspaceIDs.insert(workspace.id)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CodexTheme.secondaryText)
                        .frame(width: 25, height: 25)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("New chat in \(workspace.name)")
            }
            .background(CodexTheme.surfaceHighlight.opacity(isExpanded ? 0.42 : 0), in: RoundedRectangle(cornerRadius: 7))
            .contextMenu {
                Button("New chat in \(workspace.name)", systemImage: "plus") {
                    viewModel.newSession(inWorkspacePath: workspace.path)
                    expandedWorkspaceIDs.insert(workspace.id)
                }
                Button("Remove project", systemImage: "folder.badge.minus", role: .destructive) {
                    viewModel.removeWorkspace(workspace.id)
                    expandedWorkspaceIDs.remove(workspace.id)
                }
            }

            if isExpanded {
                let sessions = sessions(in: workspace)
                if sessions.isEmpty {
                    Button {
                        viewModel.newSession(inWorkspacePath: workspace.path)
                    } label: {
                        Text("Start a chat in this project")
                            .font(.system(size: 11.5))
                            .foregroundStyle(CodexTheme.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 35)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                } else {
                    ForEach(sessions) { session in
                        sessionRow(session, indented: true)
                    }
                }
            }
        }
    }

    private var generalChatsSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionHeading("Chat", symbol: "plus", help: "Start a general chat") {
                viewModel.newSession()
            }

            if generalSessions.isEmpty {
                Button {
                    viewModel.newSession()
                } label: {
                    Text("Start a general chat")
                        .font(.system(size: 12))
                        .foregroundStyle(CodexTheme.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            } else {
                ForEach(generalSessions) { session in
                    sessionRow(session, indented: false)
                }
            }
        }
    }

    private func sectionHeading(
        _ title: String,
        symbol: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(CodexTheme.secondaryText)
            Spacer()
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CodexTheme.secondaryText)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(help)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 1)
    }

    private func sessionRow(_ session: ChatSession, indented: Bool) -> some View {
        let isSelected = viewModel.selectedSessionId == session.id
        return Button {
            viewModel.selectSession(session.id)
        } label: {
            HStack(spacing: 8) {
                Text(session.title)
                    .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? CodexTheme.primaryText : CodexTheme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if viewModel.isGenerating(sessionID: session.id) {
                    ProgressView().controlSize(.mini).tint(CodexTheme.accentBlue)
                }
            }
            .padding(.horizontal, 9)
            .padding(.leading, indented ? 24 : 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? CodexTheme.surfaceHighlight.opacity(0.8) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete chat", systemImage: "trash", role: .destructive) {
                viewModel.deleteSession(session.id)
            }
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 8) {
            connectionIndicator
                .font(.system(size: 11))
                .frame(width: 15)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.connectionStatus.isConnected ? "Antigravity connected" : "ACP server")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(CodexTheme.primaryText)
                    .lineLimit(1)
                Text(viewModel.connectionStatus.displayText)
                    .font(.system(size: 10))
                    .foregroundStyle(CodexTheme.tertiaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                Task { await viewModel.reconnect() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(CodexTheme.tertiaryText)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Reconnect to ACP")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(CodexTheme.surface.opacity(0.32))
        .overlay(alignment: .top) { Rectangle().fill(CodexTheme.border).frame(height: 1) }
    }

    @ViewBuilder
    private var connectionIndicator: some View {
        switch viewModel.connectionStatus {
        case .connected:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(CodexTheme.accentGreen)
        case .connecting:
            ProgressView().controlSize(.small).tint(CodexTheme.accentAmber)
        case .error:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(CodexTheme.accentRed)
        case .disconnected:
            Image(systemName: "circle.dashed").foregroundStyle(CodexTheme.tertiaryText)
        }
    }

    private var filteredWorkspaces: [Workspace] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.workspaces }
        return viewModel.workspaces.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.path.localizedCaseInsensitiveContains(query) ||
            sessions(in: $0).contains(where: { $0.title.localizedCaseInsensitiveContains(query) })
        }
    }

    private var generalSessions: [ChatSession] {
        let sessions = viewModel.sessions.filter { $0.workspacePath.isEmpty }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sessions }
        return sessions.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private func sessions(in workspace: Workspace) -> [ChatSession] {
        let sessions = viewModel.sessions.filter { $0.workspacePath == workspace.path }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sessions }
        return sessions.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private func addProjectFolder() {
        let panel = NSOpenPanel()
        panel.title = "Add a Project Workspace"
        panel.message = "Choose a folder Antide should use as this project's working directory."
        panel.prompt = "Add Workspace"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            let workspace = viewModel.addWorkspace(at: url.path)
            expandedWorkspaceIDs.insert(workspace.id)
        }
    }
}
