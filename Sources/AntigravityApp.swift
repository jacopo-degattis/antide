import SwiftUI

@main
struct AntigravityApp: App {
    @StateObject private var viewModel = ChatViewModel()

    var body: some Scene {
        WindowGroup {
            HStack(spacing: 0) {
                SidebarView(viewModel: viewModel)
                ChatView(viewModel: viewModel)
            }
            .preferredColorScheme(.dark)
            .background(CodexTheme.background)
            .navigationTitle("Antide")
            .frame(minWidth: 1120, minHeight: 700)
            .onDisappear { viewModel.flushArchive() }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat Session") {
                    viewModel.newSession()
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandMenu("Antide") {
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
