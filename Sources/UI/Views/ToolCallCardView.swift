import SwiftUI

public struct ToolCallCardView: View {
    let item: ToolCallItem
    @State private var isExpanded: Bool = false
    @State private var selectedTab: Int = 0 // 0: Input/Command, 1: Output

    public init(item: ToolCallItem) {
        self.item = item
        // Start expanded if running or failed
        self._isExpanded = State(initialValue: item.status == .running || item.status == .failure)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Bar
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    // Tool Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(toolIconBackground)
                            .frame(width: 24, height: 24)

                        Image(systemName: item.sfSymbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(toolIconColor)
                    }

                    // Tool Name & Short summary
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(item.name)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(CodexTheme.primaryText)

                            Text(item.kind.uppercased())
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundColor(CodexTheme.tertiaryText)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(CodexTheme.surfaceHighlight)
                                .cornerRadius(3)
                        }

                        if !item.inputFormatted.isEmpty && !isExpanded {
                            Text(item.inputFormatted.components(separatedBy: .newlines).first ?? "")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(CodexTheme.secondaryText)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    // Status Pill & Duration
                    HStack(spacing: 6) {
                        if let ms = item.durationMs {
                            Text("\(ms)ms")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(CodexTheme.tertiaryText)
                        }

                        statusBadge

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(CodexTheme.tertiaryText)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(CodexTheme.surface)
            }
            .buttonStyle(.plain)

            // Body when expanded
            if isExpanded {
                Divider().background(CodexTheme.border)

                VStack(alignment: .leading, spacing: 8) {
                    // Tabs for Input vs Output if output exists
                    if item.outputFormatted != nil || item.errorMessage != nil {
                        HStack(spacing: 8) {
                            tabButton(title: "Command / Input", index: 0)
                            tabButton(title: "Output / Result", index: 1)
                            Spacer()
                        }
                        .padding(.top, 4)
                    }

                    if selectedTab == 0 || (item.outputFormatted == nil && item.errorMessage == nil) {
                        if !item.inputFormatted.isEmpty {
                            CodeBlockView(
                                code: item.inputFormatted,
                                language: item.kind == "bash" ? "bash" : "json"
                            )
                        } else {
                            Text("No input parameters")
                                .font(.system(size: 11))
                                .italic()
                                .foregroundColor(CodexTheme.tertiaryText)
                        }
                    } else {
                        if let err = item.errorMessage {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(CodexTheme.accentRed)
                                    .font(.system(size: 12))
                                Text(err)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(CodexTheme.accentRed)
                            }
                            .padding(8)
                            .background(CodexTheme.accentRed.opacity(0.1))
                            .cornerRadius(6)
                        }

                        if let out = item.outputFormatted {
                            CodeBlockView(
                                code: out,
                                language: item.kind == "bash" ? "stdout" : "json"
                            )
                        } else if item.errorMessage == nil {
                            Text("No output returned")
                                .font(.system(size: 11))
                                .italic()
                                .foregroundColor(CodexTheme.tertiaryText)
                        }
                    }
                }
                .padding(10)
                .background(CodexTheme.secondaryBackground.opacity(0.95))
            }
        }
        .cornerRadius(7)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(cardBorderColor, lineWidth: 1)
        )
    }

    private func tabButton(title: String, index: Int) -> some View {
        Button {
            selectedTab = index
        } label: {
            Text(title)
                .font(.system(size: 11, weight: selectedTab == index ? .semibold : .regular))
                .foregroundColor(selectedTab == index ? CodexTheme.primaryText : CodexTheme.tertiaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(selectedTab == index ? CodexTheme.surfaceHighlight : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch item.status {
        case .running:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.55)
                    .frame(width: 12, height: 12)
                Text("Running")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(CodexTheme.accentCyan)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(CodexTheme.accentCyan.opacity(0.12))
            .cornerRadius(4)

        case .success:
            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                Text("Completed")
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundColor(CodexTheme.accentGreen)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(CodexTheme.accentGreen.opacity(0.12))
            .cornerRadius(4)

        case .failure:
            HStack(spacing: 3) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                Text("Failed")
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundColor(CodexTheme.accentRed)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(CodexTheme.accentRed.opacity(0.12))
            .cornerRadius(4)

        case .pending:
            Text("Pending")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(CodexTheme.tertiaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(CodexTheme.surfaceHighlight)
                .cornerRadius(4)
        }
    }

    private var toolIconColor: Color {
        switch item.kind.lowercased() {
        case "bash", "terminal": return CodexTheme.accentAmber
        case "edit", "file_edit": return CodexTheme.accentBlue
        case "search", "grep_search": return CodexTheme.accentPurple
        default: return CodexTheme.accentCyan
        }
    }

    private var toolIconBackground: Color {
        toolIconColor.opacity(0.15)
    }

    private var cardBorderColor: Color {
        switch item.status {
        case .running: return CodexTheme.accentCyan.opacity(0.35)
        case .failure: return CodexTheme.accentRed.opacity(0.4)
        default: return CodexTheme.border
        }
    }
}
