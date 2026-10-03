import SwiftUI
import AppKit

public struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: Int = 0
    @State private var diagnostics: [DiagnosticItem] = []
    @State private var isRunningDiagnostics: Bool = false

    public init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Preferences")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(CodexTheme.primaryText)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(CodexTheme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(CodexTheme.surface)

            Divider().background(CodexTheme.border)

            // Tabs Selector
            HStack(spacing: 6) {
                tabButton("Connection", icon: "network", index: 0)
                tabButton("Agent & Models", icon: "brain", index: 1)
                tabButton("Diagnostics & Bundling", icon: "stethoscope", index: 2)
                tabButton("Telemetry Logs", icon: "terminal", index: 3)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(CodexTheme.secondaryBackground)

            Divider().background(CodexTheme.border)

            // Tab Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case 0:
                        connectionTab
                    case 1:
                        agentTab
                    case 2:
                        diagnosticsTab
                    case 3:
                        logsTab
                    default:
                        EmptyView()
                    }
                }
                .padding(20)
            }

            Divider().background(CodexTheme.border)

            // Bottom Actions
            HStack {
                StatusBadge(status: viewModel.connectionStatus)

                Spacer()

                Button("Save & Reconnect") {
                    Task {
                        await viewModel.reconnect()
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(14)
            .background(CodexTheme.surface)
        }
        .frame(width: 580, height: 500)
        .background(CodexTheme.background)
        .onAppear {
            runDiagnostics()
        }
    }

    private func tabButton(_ title: String, icon: String, index: Int) -> some View {
        Button {
            selectedTab = index
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12, weight: selectedTab == index ? .semibold : .regular))
            }
            .foregroundColor(selectedTab == index ? CodexTheme.primaryText : CodexTheme.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(selectedTab == index ? CodexTheme.surfaceHighlight : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab 1: Connection & Subprocess

    private var connectionTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Transport Mode", subtitle: "Select how the application interfaces with refined-antigravity-acp")

            Picker("Transport Mode", selection: $settings.transportMode) {
                ForEach(TransportMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if settings.transportMode == .subprocess {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Subprocess Launch Strategy", subtitle: "Choose how the child process is spawned")

                    Picker("Strategy", selection: $settings.subprocessStrategy) {
                        ForEach(SubprocessStrategy.allCases) { strategy in
                            Text(strategy.title).tag(strategy)
                        }
                    }
                    .pickerStyle(.menu)

                    VStack(alignment: .leading, spacing: 8) {
                        pathRow(title: "Custom Executable / Binary", text: $settings.customBinaryPath, canChooseFile: true)
                        pathRow(title: "Node.js Binary Path", text: $settings.nodePath, canChooseFile: true)
                        pathRow(title: "pnpm Binary Path", text: $settings.pnpmPath, canChooseFile: true)
                        pathRow(title: "Working Directory", text: $settings.workingDirectory, canChooseFile: false)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Additional CLI Arguments")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(CodexTheme.secondaryText)
                            TextField("--yes", text: $settings.customArgs)
                                .textFieldStyle(.roundedBorder)
                        }

                        Toggle("Enable REFINED_AGY_TRACE (Verbose Telemetry)", isOn: $settings.traceLogging)
                            .font(.system(size: 12))
                            .foregroundColor(CodexTheme.primaryText)
                    }
                    .padding(12)
                    .background(CodexTheme.surface.opacity(0.6))
                    .cornerRadius(8)
                }
            } else if settings.transportMode == .websocket {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Remote WebSocket Endpoint", subtitle: "Connect to an ACP proxy over TCP/WebSocket")

                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Host").font(.system(size: 11.5, weight: .medium)).foregroundColor(CodexTheme.secondaryText)
                            TextField("127.0.0.1", text: $settings.wsHost).textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Port").font(.system(size: 11.5, weight: .medium)).foregroundColor(CodexTheme.secondaryText)
                            TextField("3000", value: $settings.wsPort, format: .number).textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Path").font(.system(size: 11.5, weight: .medium)).foregroundColor(CodexTheme.secondaryText)
                            TextField("/acp", text: $settings.wsPath).textFieldStyle(.roundedBorder)
                        }
                    }

                    Toggle("Use Secure WebSocket (WSS)", isOn: $settings.wsUseSSL)
                        .font(.system(size: 12))
                        .foregroundColor(CodexTheme.primaryText)
                }
                .padding(12)
                .background(CodexTheme.surface.opacity(0.6))
                .cornerRadius(8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Interactive Demo / Mock Mode")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(CodexTheme.primaryText)
                    Text("Runs a complete local mock of the ACP streaming protocol with thinking effects, multi-step subagent plans, and terminal/file tool execution.")
                        .font(.system(size: 12))
                        .foregroundColor(CodexTheme.secondaryText)
                }
                .padding(12)
                .background(CodexTheme.surface.opacity(0.6))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Tab 2: Agent & Models

    private var agentTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Default Model & Reasoning", subtitle: "Configure model options and system prompt injection")

            VStack(alignment: .leading, spacing: 10) {
                Picker("Default Model", selection: $settings.defaultModel) {
                    ForEach(ModelOption.standardModels) { model in
                        Text(model.name).tag(model.id)
                    }
                }
                .pickerStyle(.menu)

                Picker("Reasoning Effort", selection: $settings.defaultEffort) {
                    ForEach(ReasoningEffort.allCases) { effort in
                        Text(effort.title).tag(effort)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Default Execution Mode", selection: $settings.defaultMode) {
                    ForEach(ExecutionMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemSymbol).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom System Prompt Injection (_meta.systemPrompt)")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(CodexTheme.secondaryText)

                    TextEditor(text: $settings.customSystemPrompt)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(CodexTheme.primaryText)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(height: 100)
                        .background(CodexTheme.secondaryBackground)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(CodexTheme.border, lineWidth: 1))
                }
            }
            .padding(12)
            .background(CodexTheme.surface.opacity(0.6))
            .cornerRadius(8)
        }
    }

    // MARK: - Tab 3: Diagnostics & Bundling

    private var diagnosticsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionHeader("System Diagnostics", subtitle: "Verify local runtimes and binaries on this Mac")
                Spacer()
                Button {
                    runDiagnostics()
                } label: {
                    HStack(spacing: 4) {
                        if isRunningDiagnostics {
                            ProgressView().scaleEffect(0.5)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Re-scan")
                    }
                }
                .disabled(isRunningDiagnostics)
            }

            VStack(spacing: 8) {
                ForEach(diagnostics) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.isAvailable ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundColor(item.isAvailable ? CodexTheme.accentGreen : CodexTheme.accentAmber)
                            .font(.system(size: 15))

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(item.name)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(CodexTheme.primaryText)

                                if let ver = item.version {
                                    Text(ver)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(CodexTheme.accentCyan)
                                }
                            }

                            if let path = item.path {
                                Text(path)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundColor(CodexTheme.tertiaryText)
                            }

                            Text(item.detail)
                                .font(.system(size: 11))
                                .foregroundColor(CodexTheme.secondaryText)
                        }

                        Spacer()
                    }
                    .padding(10)
                    .background(CodexTheme.surface.opacity(0.6))
                    .cornerRadius(6)
                }
            }

            sectionHeader("Bundling refined-antigravity-acp in .app", subtitle: "How to ship as a standalone macOS application")

            Text("You can embed the Node runtime and refined-antigravity-acp package directly inside the app bundle's Contents/Resources/bin folder. Run the provided script:")
                .font(.system(size: 12))
                .foregroundColor(CodexTheme.secondaryText)

            CodeBlockView(
                code: "./Scripts/bundle-acp.sh",
                language: "bash"
            )
        }
    }

    // MARK: - Tab 4: Telemetry Logs

    private var logsTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Process Telemetry & Stderr Logs", subtitle: "Real-time stream from the supervisor subprocess")

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 3) {
                        if viewModel.telemetryLogs.isEmpty {
                            Text("No telemetry logs yet.")
                                .font(.system(size: 12))
                                .italic()
                                .foregroundColor(CodexTheme.tertiaryText)
                        } else {
                            ForEach(Array(viewModel.telemetryLogs.enumerated()), id: \.offset) { idx, log in
                                Text(log)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundColor(log.contains("error") || log.contains("Error") ? CodexTheme.accentRed : CodexTheme.secondaryText)
                                    .textSelection(.enabled)
                                    .id(idx)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 280)
                .background(CodexTheme.secondaryBackground)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(CodexTheme.border, lineWidth: 1))
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(CodexTheme.primaryText)
            Text(subtitle)
                .font(.system(size: 11.5))
                .foregroundColor(CodexTheme.tertiaryText)
        }
    }

    private func pathRow(title: String, text: Binding<String>, canChooseFile: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(CodexTheme.secondaryText)

            HStack {
                TextField("", text: text)
                    .textFieldStyle(.roundedBorder)

                Button("Browse...") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = canChooseFile
                    panel.canChooseDirectories = !canChooseFile
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        text.wrappedValue = url.path
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(CodexTheme.surfaceHighlight)
                .cornerRadius(4)
            }
        }
    }

    private func runDiagnostics() {
        isRunningDiagnostics = true
        Task {
            let res = await SystemDiagnostics.runDiagnostics()
            await MainActor.run {
                self.diagnostics = res
                self.isRunningDiagnostics = false
            }
        }
    }
}
