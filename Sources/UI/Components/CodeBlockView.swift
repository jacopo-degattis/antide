import SwiftUI
import AppKit

public struct CodeBlockView: View {
    let code: String
    let language: String?
    @State private var copied: Bool = false

    public init(code: String, language: String? = nil) {
        self.code = code
        self.language = language
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack {
                if let lang = language, !lang.isEmpty {
                    Text(lang.uppercased())
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))     // Increased (was 11)
                        .foregroundColor(CodexTheme.secondaryText)
                } else {
                    Text("CODE")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))     // Increased (was 11)
                        .foregroundColor(CodexTheme.secondaryText)
                }

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    withAnimation {
                        copied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation {
                            copied = false
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))          // Increased (was 10)
                        Text(copied ? "Copied" : "Copy")
                            .font(.system(size: 12, weight: .medium))    // Increased (was 11)
                    }
                    .foregroundColor(copied ? CodexTheme.accentGreen : CodexTheme.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(CodexTheme.surfaceHighlight.opacity(0.6))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(CodexTheme.surface.opacity(0.9))

            Divider().background(CodexTheme.border)

            // Content
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(size: 13.5, design: .monospaced))    // Increased (was 12.5)
                    .foregroundColor(CodexTheme.primaryText)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(CodexTheme.secondaryBackground)
        }
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(CodexTheme.border, lineWidth: 1)
        )
    }
}
