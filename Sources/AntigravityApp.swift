import SwiftUI

@main
struct AntigravityApp: App {
    @StateObject private var viewModel = ChatViewModel()

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                SidebarView(viewModel: viewModel)
            } detail: {
                ChatView(viewModel: viewModel)
            }
            .preferredColorScheme(.dark)
            .background(CodexTheme.background)
            .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat Session") {
                    viewModel.newSession()
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandMenu("Antigravity") {
                Button("Cancel Current Turn") {
                    viewModel.cancelTurn()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!viewModel.isGenerating)

                Button("Reconnect to ACP Server") {
                    Task {
                        await viewModel.reconnect()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

            }
        }

        #if os(macOS)
        Settings {
            SettingsView(viewModel: viewModel)
                .preferredColorScheme(.dark)
        }
        #endif
    }
}
