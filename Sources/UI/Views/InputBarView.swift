import AppKit
import SwiftUI

public struct InputBarView: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState private var isFocused: Bool

    public init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isGenerating
    }

    public var body: some View {
        VStack(spacing: 0) {
            contextBar
                .padding(.bottom, -1)

            VStack(spacing: 0) {
                editor
                    .padding(.horizontal, 12)
                    .padding(.top, 7)
                    .padding(.bottom, 2)

                HStack(spacing: 7) {
                    attachmentMenu
                    modePicker
                    Spacer(minLength: 8)
                    modelPicker
                    effortPicker
                    turnButton
                }
                .padding(.horizontal, 11)
                .padding(.bottom, 7)
            }
            .background(CodexTheme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(isFocused ? Color.white.opacity(0.20) : CodexTheme.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 20, y: 6)

            Text("Antigravity can make mistakes. Review important changes.")
                .font(.system(size: 10.5))
                .foregroundStyle(CodexTheme.tertiaryText)
                .padding(.top, 8)
        }
        .frame(maxWidth: 830)
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 19)
    }

    private var contextBar: some View {
        HStack(spacing: 4) {
            Menu {
                Button {
                    chooseWorkspace()
                } label: {
                    Label("Choose workspace…", systemImage: "folder")
                }
                Button {
                    if let id = viewModel.selectedSessionId {
                        viewModel.moveSession(id, toWorkspacePath: nil)
                    }
                } label: {
                    Label("Move to general chat", systemImage: "bubble.left")
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: workspacePath.isEmpty ? "bubble.left" : "folder")
                    Text(workspaceName)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(CodexTheme.tertiaryText)
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(CodexTheme.secondaryText)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .contentShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(workspacePath.isEmpty ? "General chat — no project folder" : workspacePath)

            contextDivider

            HStack(spacing: 6) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 6, height: 6)
                Text("Local")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(CodexTheme.secondaryText)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .help(viewModel.connectionStatus.displayText)

            Spacer(minLength: 0)

            Button {
                Task { await viewModel.reconnect() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CodexTheme.tertiaryText)
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Reconnect to ACP")
        }
        .padding(.horizontal, 5)
    }

    private var contextDivider: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(CodexTheme.border)
            .frame(width: 1, height: 16)
    }

    private var editor: some View {
        TextField("Ask anything, or describe what you want to build", text: $viewModel.inputText, axis: .vertical)
            .font(.system(size: 14))
            .foregroundStyle(CodexTheme.primaryText)
            .textFieldStyle(.plain)
            .lineLimit(1...4)
            .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 112, alignment: .topLeading)
            .focused($isFocused)
            .onKeyPress(.return, phases: .down) { press in
                if press.modifiers.contains(.shift) { return .ignored }
                guard canSend else { return .handled }
                viewModel.sendCurrentPrompt()
                return .handled
            }
    }

    private var attachmentMenu: some View {
        Menu {
            Button(action: chooseWorkspace) {
                Label("Add workspace folder", systemImage: "folder.badge.plus")
            }
            Button {
                viewModel.inputText += "@"
                isFocused = true
            } label: {
                Label("Mention a file or folder", systemImage: "at")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(CodexTheme.secondaryText)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .help("Add context")
    }

    private var modePicker: some View {
        Menu {
            ForEach(ExecutionMode.allCases) { mode in
                Button {
                    if let index = activeSessionIndex { viewModel.sessions[index].mode = mode }
                } label: {
                    if currentMode == mode {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Label(mode.title, systemImage: mode.systemSymbol)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: currentMode.systemSymbol)
                    .font(.system(size: 11))
                Text(currentMode == .default ? "Approve for me" : currentMode.title)
                    .font(.system(size: 11.5, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(CodexTheme.tertiaryText)
            }
            .foregroundStyle(CodexTheme.secondaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Choose how the agent handles approvals")
    }

    private var modelPicker: some View {
        Menu {
            ForEach(ModelOption.standardModels) { model in
                Button {
                    if let index = activeSessionIndex { viewModel.sessions[index].modelId = model.id }
                } label: {
                    if currentModel == model.id {
                        Label(model.name, systemImage: "checkmark")
                    } else {
                        Text(model.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(modelShortName)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(CodexTheme.secondaryText)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(CodexTheme.tertiaryText)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 7)
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Select model")
    }

    private var effortPicker: some View {
        Menu {
            ForEach(ReasoningEffort.allCases) { effort in
                Button {
                    if let index = activeSessionIndex { viewModel.sessions[index].reasoningEffort = effort }
                } label: {
                    if currentEffort == effort {
                        Label(effort.title, systemImage: "checkmark")
                    } else {
                        Text(effort.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(currentEffort.title.replacingOccurrences(of: " Effort", with: ""))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(CodexTheme.secondaryText)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(CodexTheme.tertiaryText)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 7)
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Reasoning effort")
    }

    private var turnButton: some View {
        Button {
            if viewModel.isGenerating {
                viewModel.cancelTurn()
            } else if canSend {
                viewModel.sendCurrentPrompt()
            }
        } label: {
            Image(systemName: viewModel.isGenerating ? "stop.fill" : "arrow.up")
                .font(.system(size: viewModel.isGenerating ? 12 : 15, weight: .semibold))
                .foregroundStyle(.white.opacity(canSend || viewModel.isGenerating ? 1 : 0.5))
                .frame(width: 32, height: 32)
                .background(
                    viewModel.isGenerating ? CodexTheme.accentRed : CodexTheme.accentBlue,
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSend && !viewModel.isGenerating)
        .help(viewModel.isGenerating ? "Stop generation (⌘.)" : "Send message (Return)")
    }

    private var currentMode: ExecutionMode { viewModel.activeSession?.mode ?? .default }
    private var currentModel: String { viewModel.activeSession?.modelId ?? "gemini-3.1-pro" }
    private var currentEffort: ReasoningEffort { viewModel.activeSession?.reasoningEffort ?? .high }
    private var activeSessionIndex: Int? {
        guard let id = viewModel.selectedSessionId else { return nil }
        return viewModel.sessions.firstIndex(where: { $0.id == id })
    }

    private var workspacePath: String {
        viewModel.activeSession?.workspacePath ?? ""
    }

    private var workspaceName: String {
        guard !workspacePath.isEmpty else { return "General chat" }
        let name = URL(fileURLWithPath: workspacePath).lastPathComponent
        return name.isEmpty ? "Workspace" : name
    }

    private var modelShortName: String {
        ModelOption.standardModels.first(where: { $0.id == currentModel })?.name.components(separatedBy: " (").first ?? currentModel
    }

    private var connectionColor: Color {
        switch viewModel.connectionStatus {
        case .connected: CodexTheme.accentGreen
        case .connecting: CodexTheme.accentAmber
        case .error: CodexTheme.accentRed
        case .disconnected: CodexTheme.tertiaryText
        }
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
}
