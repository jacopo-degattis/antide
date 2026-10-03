import AppKit
import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var viewModel: ChatViewModel
    @State private var diagnostics: [DiagnosticItem] = []
    @State private var isRunningDiagnostics = false
    @State private var isReconnecting = false
    @State private var didReconnect = false

    public init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        TabView {
            connectionTab
                .tabItem { Label("Connection", systemImage: "network") }

            agentTab
                .tabItem { Label("Agent", systemImage: "sparkles") }

            diagnosticsTab
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }

            logsTab
                .tabItem { Label("Logs", systemImage: "terminal") }
        }
        .frame(width: 760, height: 560)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            settingsFooter
        }
        .background(CodexTheme.background)
        .task {
            if diagnostics.isEmpty { await runDiagnostics() }
        }
    }

    private var connectionTab: some View {
        Form {
            Section {
                Picker("Connect using", selection: $settings.transportMode) {
                    ForEach(TransportMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if settings.transportMode == .subprocess {
                    Picker("Server launch", selection: $settings.subprocessStrategy) {
                        ForEach(SubprocessStrategy.allCases) { strategy in
                            Text(strategy.title).tag(strategy)
                        }
                    }

                    if settings.subprocessStrategy == .customPath || settings.subprocessStrategy == .globalBinary {
                        pathRow("ACP executable", value: $settings.customBinaryPath, chooseDirectory: false)
                    }

                    LabeledContent("Workspace") {
                        HStack(spacing: 8) {
                            TextField("Project folder", text: $settings.workingDirectory)
                                .textFieldStyle(.roundedBorder)
                            Button("Choose…") { choosePath($settings.workingDirectory, directory: true) }
                        }
                    }

                    DisclosureGroup("Advanced subprocess options") {
                        VStack(spacing: 11) {
                            pathRow("Node.js", value: $settings.nodePath, chooseDirectory: false)
                            pathRow("pnpm", value: $settings.pnpmPath, chooseDirectory: false)
                            LabeledContent("Extra server arguments") {
                                TextField("Optional", text: $settings.customArgs)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Toggle("Verbose ACP telemetry", isOn: $settings.traceLogging)
                        }
                        .padding(.top, 8)
                    }
                } else if settings.transportMode == .websocket {
                    HStack(spacing: 12) {
                        LabeledContent("Host") {
                            TextField("127.0.0.1", text: $settings.wsHost)
                                .textFieldStyle(.roundedBorder)
                        }
                        .frame(maxWidth: .infinity)
                        LabeledContent("Port") {
                            TextField("3000", value: $settings.wsPort, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 95)
                        }
                    }
                    LabeledContent("Path") {
                        TextField("/acp", text: $settings.wsPath)
                            .textFieldStyle(.roundedBorder)
                    }
                    Toggle("Use secure WebSocket (wss://)", isOn: $settings.wsUseSSL)
                    LabeledContent("Endpoint preview") {
                        Text(settings.webSocketURL?.absoluteString ?? "Invalid endpoint")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(CodexTheme.secondaryText)
                            .textSelection(.enabled)
                    }
                } else {
                    Label("Demo transport is active", systemImage: "sparkles.rectangle.stack")
                        .foregroundStyle(CodexTheme.secondaryText)
                    Text("Uses a local protocol simulator. Switch to Local Subprocess to connect to refined-antigravity-acp.")
                        .font(.callout)
                        .foregroundStyle(CodexTheme.tertiaryText)
                }
            } header: {
                settingsSectionHeader("ACP Server", subtitle: "Choose how this app connects to your Antigravity agent.")
            }

            Section("Connection status") {
                HStack(spacing: 10) {
                    connectionGlyph
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusTitle)
                            .font(.system(size: 13, weight: .medium))
                        Text(viewModel.connectionStatus.displayText)
                            .font(.system(size: 11.5))
                            .foregroundStyle(CodexTheme.tertiaryText)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button {
                        Task { await reconnect() }
                    } label: {
                        if isReconnecting {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Reconnect", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isReconnecting)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 24)
        .padding(.top, 15)
    }

    private var agentTab: some View {
        Form {
            Section {
                Picker("Model", selection: $settings.defaultModel) {
                    ForEach(ModelOption.standardModels) { model in
                        Text(model.name).tag(model.id)
                    }
                }
                Picker("Reasoning effort", selection: $settings.defaultEffort) {
                    ForEach(ReasoningEffort.allCases) { effort in
                        Text(effort.title).tag(effort)
                    }
                }
                Picker("Approval behavior", selection: $settings.defaultMode) {
                    ForEach(ExecutionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } header: {
                settingsSectionHeader("Agent defaults", subtitle: "Used for new conversations. You can change these per chat.")
            }

            Section {
                TextEditor(text: $settings.customSystemPrompt)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 105)
                    .padding(7)
                    .background(CodexTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(CodexTheme.border))
                Text("Optional workspace instructions are sent through the ACP _meta.systemPrompt extension.")
                    .font(.caption)
                    .foregroundStyle(CodexTheme.tertiaryText)
            } header: {
                Text("System instructions")
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 24)
        .padding(.top, 15)
    }

    private var diagnosticsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("System diagnostics")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CodexTheme.primaryText)
                    Text("Runtime and server discovery on this Mac.")
                        .font(.system(size: 12))
                        .foregroundStyle(CodexTheme.tertiaryText)
                }
                Spacer()
                Button {
                    Task { await runDiagnostics() }
                } label: {
                    Label("Scan again", systemImage: "arrow.clockwise")
                }
                .disabled(isRunningDiagnostics)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            if isRunningDiagnostics && diagnostics.isEmpty {
                ProgressView("Checking runtimes…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(diagnostics) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.isAvailable ? "checkmark.circle.fill" : "minus.circle")
                            .font(.system(size: 17))
                            .foregroundStyle(item.isAvailable ? CodexTheme.accentGreen : CodexTheme.tertiaryText)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 7) {
                                Text(item.name).font(.system(size: 12.5, weight: .medium))
                                if let version = item.version {
                                    Text(version)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(CodexTheme.secondaryText)
                                }
                            }
                            Text(item.path ?? item.detail)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(CodexTheme.tertiaryText)
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 3)
                    .listRowBackground(CodexTheme.surface.opacity(0.6))
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 16)
            }
        }
        .background(CodexTheme.background)
    }

    private var logsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ACP process logs")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CodexTheme.primaryText)
                    Text("Server startup messages, protocol traces, and errors.")
                        .font(.system(size: 12))
                        .foregroundStyle(CodexTheme.tertiaryText)
                }
                Spacer()
                Button("Clear") { viewModel.telemetryLogs.removeAll() }
                    .disabled(viewModel.telemetryLogs.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if viewModel.telemetryLogs.isEmpty {
                            ContentUnavailableView("No logs yet", systemImage: "text.alignleft", description: Text("ACP server output will appear here."))
                                .padding(.top, 50)
                        } else {
                            ForEach(Array(viewModel.telemetryLogs.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(logColor(line))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                    }
                    .padding(14)
                }
                .onChange(of: viewModel.telemetryLogs.count) { _, _ in
                    if let last = viewModel.telemetryLogs.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            .background(CodexTheme.surface.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(CodexTheme.border))
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .background(CodexTheme.background)
    }

    private var settingsFooter: some View {
        HStack(spacing: 10) {
            Text(isReconnecting ? "Connecting to ACP…" : (didReconnect ? viewModel.connectionStatus.displayText : "Settings are saved automatically"))
                .font(.system(size: 11))
                .foregroundStyle(didReconnect && !viewModel.connectionStatus.isConnected ? CodexTheme.accentAmber : CodexTheme.tertiaryText)
            Spacer()
            Button("Reconnect and apply") {
                Task { await reconnect() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(isReconnecting)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(CodexTheme.border).frame(height: 1) }
    }

    private var connectionGlyph: some View {
        Group {
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
        .font(.system(size: 17))
        .frame(width: 26, height: 26)
    }

    private var statusTitle: String {
        switch viewModel.connectionStatus {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .error: "Could not connect"
        case .disconnected: "Disconnected"
        }
    }

    private func settingsSectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(CodexTheme.primaryText)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(CodexTheme.tertiaryText)
        }
        .padding(.bottom, 3)
    }

    private func pathRow(_ title: String, value: Binding<String>, chooseDirectory: Bool) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                TextField("Path", text: value)
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") { choosePath(value, directory: chooseDirectory) }
            }
        }
    }

    private func choosePath(_ value: Binding<String>, directory: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !directory
        panel.canChooseDirectories = directory
        panel.canCreateDirectories = directory
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { value.wrappedValue = url.path }
    }

    private func logColor(_ line: String) -> Color {
        if line.localizedCaseInsensitiveContains("error") || line.localizedCaseInsensitiveContains("failed") {
            return CodexTheme.accentRed
        }
        if line.localizedCaseInsensitiveContains("warning") { return CodexTheme.accentAmber }
        return CodexTheme.secondaryText
    }

    @MainActor
    private func runDiagnostics() async {
        guard !isRunningDiagnostics else { return }
        isRunningDiagnostics = true
        diagnostics = await SystemDiagnostics.runDiagnostics()
        isRunningDiagnostics = false
    }

    @MainActor
    private func reconnect() async {
        isReconnecting = true
        didReconnect = false
        await viewModel.reconnect()
        isReconnecting = false
        didReconnect = true
    }
}
