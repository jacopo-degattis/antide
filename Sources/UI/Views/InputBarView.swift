import SwiftUI
import AppKit

public struct InputBarView: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState private var isFocused: Bool

    public init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Main Input Container
            VStack(spacing: 0) {
                // Text Editor
                ZStack(alignment: .topLeading) {
                    if viewModel.inputText.isEmpty {
                        Text("Ask Antigravity anything, plan an action, or run tools...")
                            .font(.system(size: 13.5))
                            .foregroundColor(CodexTheme.tertiaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $viewModel.inputText)
                        .font(.system(size: 13.5))
                        .foregroundColor(CodexTheme.primaryText)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(minHeight: 44, maxHeight: 160)
                        .focused($isFocused)
                        .onKeyPress(.return, phases: .down) { press in
                            if press.modifiers.contains(.shift) {
                                return .ignored
                            }
                            viewModel.sendCurrentPrompt()
                            return .handled
                        }
                }

                Divider().background(CodexTheme.border.opacity(0.6))

                // Bottom toolbar row
                HStack(spacing: 8) {
                    // Working Directory Pill
                    workspacePicker

                    // Execution Mode Selector
                    modePicker

                    // Model Selector
                    modelPicker

                    Spacer()

                    // Send or Cancel Button
                    if viewModel.isGenerating {
                        Button {
                            viewModel.cancelTurn()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 10))
                                Text("Stop")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(CodexTheme.accentRed)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(CodexTheme.accentRed.opacity(0.15))
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(CodexTheme.accentRed.opacity(0.4), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Cancel current generation (Cmd+.)")
                    } else {
                        Button {
                            viewModel.sendCurrentPrompt()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(
                                    viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? CodexTheme.surfaceHighlight
                                        : CodexTheme.accentBlue
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Send prompt (Return)")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(CodexTheme.surface.opacity(0.5))
            }
            .background(CodexTheme.secondaryBackground)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isFocused ? CodexTheme.accentBlue.opacity(0.6) : CodexTheme.border,
                        lineWidth: 1
                    )
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    // MARK: - Subviews

    private var workspacePicker: some View {
        Button {
            chooseFolder()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.system(size: 10.5))
                    .foregroundColor(CodexTheme.secondaryText)

                Text(currentFolderDisplayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CodexTheme.secondaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(CodexTheme.surfaceHighlight.opacity(0.6))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help("Change active workspace directory")
    }

    private var modePicker: some View {
        Menu {
            ForEach(ExecutionMode.allCases) { mode in
                Button {
                    if let sId = viewModel.selectedSessionId,
                       let idx = viewModel.sessions.firstIndex(where: { $0.id == sId }) {
                        viewModel.sessions[idx].mode = mode
                    }
                } label: {
                    HStack {
                        Image(systemName: mode.systemSymbol)
                        Text(mode.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: currentMode.systemSymbol)
                    .font(.system(size: 10))
                    .foregroundColor(currentModeColor)

                Text(currentMode.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(currentModeColor)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundColor(CodexTheme.tertiaryText)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(currentModeColor.opacity(0.12))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(currentModeColor.opacity(0.25), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Execution mode (Default, YOLO, Plan, Accept Edits)")
    }

    private var modelPicker: some View {
        Menu {
            ForEach(ModelOption.standardModels) { model in
                Button {
                    if let sId = viewModel.selectedSessionId,
                       let idx = viewModel.sessions.firstIndex(where: { $0.id == sId }) {
                        viewModel.sessions[idx].modelId = model.id
                    }
                } label: {
                    Text(model.name)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 10))
                    .foregroundColor(CodexTheme.secondaryText)

                Text(currentModelDisplayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CodexTheme.secondaryText)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundColor(CodexTheme.tertiaryText)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(CodexTheme.surfaceHighlight.opacity(0.6))
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Select AI Model")
    }

    private var currentMode: ExecutionMode {
        viewModel.activeSession?.mode ?? .default
    }

    private var currentModeColor: Color {
        switch currentMode {
        case .yolo: return CodexTheme.accentAmber
        case .autoEdit: return CodexTheme.accentCyan
        case .plan: return CodexTheme.accentPurple
        default: return CodexTheme.accentGreen
        }
    }

    private var currentModelDisplayName: String {
        let mId = viewModel.activeSession?.modelId ?? "gemini-3.1-pro"
        return ModelOption.standardModels.first(where: { $0.id == mId })?.name.components(separatedBy: " ").first ?? mId
    }

    private var currentFolderDisplayName: String {
        let path = viewModel.activeSession?.workspacePath ?? FileManager.default.currentDirectoryPath
        let url = URL(fileURLWithPath: path)
        return url.lastPathComponent.isEmpty ? path : url.lastPathComponent
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            if let sId = viewModel.selectedSessionId,
               let idx = viewModel.sessions.firstIndex(where: { $0.id == sId }) {
                viewModel.sessions[idx].workspacePath = url.path
            }
        }
    }
}
