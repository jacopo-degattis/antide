import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct InputBarView: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState private var isFocused: Bool
    @State private var isDropTargeted = false

    public init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    private var canSend: Bool {
        (!viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.pendingAttachments.isEmpty)
            && !viewModel.isGenerating
    }

    public var body: some View {
        VStack(spacing: 0) {
            contextBar
                .padding(.bottom, -1)

            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    // Attachment chips shown above the editor
                    attachmentChips

                    editor
                        .padding(.horizontal, 12)
                        .padding(.top, 12)       // Increased top padding (was 7)
                        .padding(.bottom, 3)      // Slightly more bottom padding (was 2)
                }

                HStack(spacing: 10) {             // Increased spacing (was 7)
                    attachmentMenu
                    yoloBadge
                    Spacer(minLength: 8)
                    modelPicker
                    effortPicker
                    turnButton
                }
                .padding(.horizontal, 12)         // Slightly more horizontal padding (was 11)
                .padding(.bottom, 8)              // Slightly more bottom padding (was 7)
            }
            .background(CodexTheme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(
                        isDropTargeted ? CodexTheme.accentBlue : (isFocused ? Color.white.opacity(0.20) : CodexTheme.border),
                        lineWidth: isDropTargeted ? 2 : 1
                    )
            }
            .shadow(color: .black.opacity(0.18), radius: 20, y: 6)
            .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: handleFileDrop)

            Text("Antigravity can make mistakes. Review important changes.")
                .font(.system(size: 11))          // Increased (was 10.5)
                .foregroundStyle(CodexTheme.tertiaryText)
                .padding(.top, 9)                 // Slightly more (was 8)
        }
        .frame(maxWidth: 830)
        .padding(.horizontal, 24)
        .padding(.top, 12)                        // Increased (was 10)
        .padding(.bottom, 20)                     // Slightly more (was 19)
    }

    /// Displays attached file chips above the text input.
    private var attachmentChips: some View {
        Group {
            if !viewModel.pendingAttachments.isEmpty {
                LazyVStack(spacing: 6) {
                    ForEach(viewModel.pendingAttachments) { attach in
                        attachmentChip(attach)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    /// A single file attachment chip with name, size, and remove button.
    private func attachmentChip(_ attach: FileAttachment) -> some View {
        HStack(spacing: 8) {
            Image(systemName: attach.iconName)
                .font(.system(size: 12))
                .foregroundStyle(CodexTheme.secondaryText)

            VStack(alignment: .leading, spacing: 2) {
                Text(attach.fileName)
                    .font(.system(size: 12.5, weight: .medium))     // Increased (was 11.5)
                    .foregroundStyle(CodexTheme.primaryText)
                    .lineLimit(1)
                Text(attach.formattedSize)
                    .font(.system(size: 11))                         // Increased (was 10.5)
                    .foregroundStyle(CodexTheme.tertiaryText)
            }

            Spacer()

            Button {
                viewModel.removeAttachment(attach.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CodexTheme.tertiaryText)
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Remove file")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(CodexTheme.surfaceHighlight.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var contextBar: some View {
        HStack(spacing: 5) {                      // Slightly increased (was 4)
            HStack(spacing: 6) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 7, height: 7)                             // Slightly larger (was 6)
                Text("Local")
                    .font(.system(size: 12.5, weight: .medium))             // Increased (was 11.5)
                    .foregroundStyle(CodexTheme.secondaryText)
            }
            .padding(.horizontal, 10)                                        // Increased (was 9)
            .padding(.vertical, 8)                                           // Increased (was 7)
            .help(viewModel.connectionStatus.displayText)

            Spacer(minLength: 0)

            Button {
                Task { await viewModel.reconnect() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))               // Increased (was 11)
                    .foregroundStyle(CodexTheme.tertiaryText)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Reconnect to ACP")
        }
        .padding(.horizontal, 5)
    }

    private var editor: some View {
        TextField("Ask anything, or describe what you want to build", text: $viewModel.inputText, axis: .vertical)
            .font(.system(size: 15))                                         // Increased (was 14)
            .foregroundStyle(CodexTheme.primaryText)
            .textFieldStyle(.plain)
            .lineLimit(1...2)
            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 60, alignment: .topLeading)
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
            Button {
                chooseFiles()
            } label: {
                Label("Attach file…", systemImage: "doc")
            }
            Button {
                chooseImages()
            } label: {
                Label("Attach image…", systemImage: "photo")
            }
            Divider()
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
            Image(systemName: viewModel.pendingAttachments.isEmpty ? "plus" : "doc.badge.plus")
                .font(.system(size: 16, weight: .medium))                  // Increased (was 15)
                .foregroundStyle(CodexTheme.secondaryText)
                .frame(width: 32, height: 32)                              // Larger hit area (was 30)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .help("Add context or attach files")
    }

    private var yoloBadge: some View {
        HStack(spacing: 7) {                                               // Slightly more (was 6)
            Image(systemName: ExecutionMode.yolo.systemSymbol)
                .font(.system(size: 12))                                   // Increased (was 11)
            Text("YOLO")
                .font(.system(size: 12.5, weight: .semibold))              // Increased (was 11.5)
        }
        .foregroundStyle(CodexTheme.accentAmber)
        .padding(.horizontal, 10)                                          // Increased (was 9)
        .padding(.vertical, 8)                                             // Increased (was 7)
        .help("YOLO mode: tool and command permissions are accepted automatically")
    }

    private var modelPicker: some View {
        Menu {
            ForEach(ModelOption.standardModels) { model in
                Button {
                    SettingsManager.shared.defaultModel = model.id
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
            HStack(spacing: 6) {                                           // Slightly more (was 5)
                Text(modelShortName)
                    .font(.system(size: 12.5, weight: .medium))            // Increased (was 11.5)
                    .foregroundStyle(CodexTheme.secondaryText)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))             // Increased (was 8)
                    .foregroundStyle(CodexTheme.tertiaryText)
            }
            .padding(.horizontal, 8)                                       // Increased (was 7)
            .padding(.vertical, 8)                                         // Increased (was 7)
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
                    SettingsManager.shared.defaultEffort = effort
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
            HStack(spacing: 6) {                                           // Slightly more (was 5)
                Text(currentEffort.title.replacingOccurrences(of: " Effort", with: ""))
                    .font(.system(size: 12.5, weight: .medium))            // Increased (was 11.5)
                    .foregroundStyle(CodexTheme.secondaryText)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))             // Increased (was 8)
                    .foregroundStyle(CodexTheme.tertiaryText)
            }
            .padding(.horizontal, 8)                                       // Increased (was 7)
            .padding(.vertical, 8)                                         // Increased (was 7)
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
                .font(.system(size: viewModel.isGenerating ? 13 : 16, weight: .semibold))  // Increased (was 12/15)
                .foregroundStyle(.white.opacity(canSend || viewModel.isGenerating ? 1 : 0.5))
                .frame(width: 34, height: 34)                                                  // Larger (was 32)
                .background(
                    viewModel.isGenerating ? CodexTheme.accentRed : CodexTheme.accentBlue,
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSend && !viewModel.isGenerating)
        .help(viewModel.isGenerating ? "Stop generation (⌘.)" : "Send message (Return)")
    }

    private var currentModel: String { viewModel.activeSession?.modelId ?? SettingsManager.shared.defaultModel }
    private var currentEffort: ReasoningEffort { viewModel.activeSession?.reasoningEffort ?? SettingsManager.shared.defaultEffort }
    private var activeSessionIndex: Int? {
        guard let id = viewModel.selectedSessionId else { return nil }
        return viewModel.sessions.firstIndex(where: { $0.id == id })
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

    private func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }

        for provider in providers where provider.canLoadObject(ofClass: NSURL.self) {
            provider.loadObject(ofClass: NSURL.self) { droppedObject, _ in
                guard let droppedURL = droppedObject as? NSURL, droppedURL.isFileURL else { return }
                let url = droppedURL as URL
                DispatchQueue.main.async {
                    attachFile(at: url)
                }
            }
        }

        return true
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            attachFile(at: url)
        }
    }

    private func chooseImages() {
        chooseFiles()
    }

    private func attachFile(at url: URL) {
        let filePath = url.path
        let fileName = url.lastPathComponent
        let mimeType = inferMIMEType(fileName: fileName)

        // Read file content and size
        var fileSize = 0
        var fileContent = ""
        if let rawData = try? Data(contentsOf: url) {
            fileSize = rawData.count
            // For text-based files, read as UTF-8
            if mimeType.hasPrefix("text/") || mimeType == "application/json" {
                fileContent = String(data: rawData, encoding: .utf8) ?? ""
            }
        }

        let attachment = FileAttachment(
            fileName: fileName,
            filePath: filePath,
            mimeType: mimeType,
            sizeBytes: fileSize,
            content: fileContent
        )
        viewModel.addAttachment(attachment)
    }

    private func inferMIMEType(fileName: String) -> String {
        let lower = fileName.lowercased()
        if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "image/jpeg" }
        if lower.hasSuffix(".png") { return "image/png" }
        if lower.hasSuffix(".gif") { return "image/gif" }
        if lower.hasSuffix(".webp") { return "image/webp" }
        if lower.hasSuffix(".svg") { return "image/svg+xml" }
        if lower.hasSuffix(".pdf") { return "application/pdf" }
        if lower.hasSuffix(".json") { return "application/json" }
        if lower.hasSuffix(".md") || lower.hasSuffix(".markdown") { return "text/markdown" }
        if lower.hasSuffix(".txt") { return "text/plain" }
        if lower.hasSuffix(".html") || lower.hasSuffix(".htm") { return "text/html" }
        if lower.hasSuffix(".css") { return "text/css" }
        if lower.hasSuffix(".js") { return "text/javascript" }
        if lower.hasSuffix(".ts") || lower.hasSuffix(".tsx") { return "text/typescript" }
        if lower.hasSuffix(".py") { return "text/x-python" }
        if lower.hasSuffix(".swift") { return "text/x-swift" }
        if lower.hasSuffix(".rs") { return "text/rust" }
        if lower.hasSuffix(".go") { return "text/x-go" }
        if lower.hasSuffix(".yaml") || lower.hasSuffix(".yml") { return "text/yaml" }
        if lower.hasSuffix(".toml") { return "text/toml" }
        if lower.hasSuffix(".xml") { return "text/xml" }
        if lower.hasSuffix(".zip") { return "application/zip" }
        if lower.hasSuffix(".tar") { return "application/x-tar" }
        if lower.hasSuffix(".gz") { return "application/gzip" }
        return "application/octet-stream"
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