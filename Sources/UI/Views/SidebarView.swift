import SwiftUI

public struct SidebarView: View {
    @ObservedObject var viewModel: ChatViewModel

    public init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header / New Chat Button
            HStack {
                Text("Chats")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(CodexTheme.secondaryText)

                Spacer()

                Button {
                    viewModel.newSession()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(CodexTheme.primaryText)
                        .padding(6)
                        .background(CodexTheme.surfaceHighlight.opacity(0.6))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("New Chat (Cmd+N)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().background(CodexTheme.border)

            // Session List
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.sessions) { session in
                        sessionRow(session)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 0)

            Divider().background(CodexTheme.border)

            // Bottom Status & Settings Bar
            HStack(spacing: 8) {
                StatusBadge(status: viewModel.connectionStatus) {
                    Task {
                        await viewModel.reconnect()
                    }
                }

                Spacer()

                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundColor(CodexTheme.secondaryText)
                        .padding(6)
                        .background(CodexTheme.surfaceHighlight.opacity(0.5))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Preferences (Cmd+,)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(CodexTheme.surface.opacity(0.6))
        }
        .frame(minWidth: 220, idealWidth: 250, maxWidth: 300)
        .background(CodexTheme.background)
    }

    private func sessionRow(_ session: ChatSession) -> some View {
        let isSelected = viewModel.selectedSessionId == session.id

        return Button {
            viewModel.selectSession(session.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: session.mode.systemSymbol)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? CodexTheme.accentBlue : CodexTheme.tertiaryText)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? CodexTheme.primaryText : CodexTheme.secondaryText)
                        .lineLimit(1)

                    Text(session.updatedAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10.5))
                        .foregroundColor(CodexTheme.tertiaryText)
                }

                Spacer()

                // Delete button on hover
                Button {
                    viewModel.deleteSession(session.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(CodexTheme.tertiaryText)
                        .opacity(isSelected ? 0.7 : 0)
                }
                .buttonStyle(.plain)
                .help("Delete Session")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isSelected
                    ? CodexTheme.surfaceHighlight.opacity(0.7)
                    : Color.clear
            )
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
