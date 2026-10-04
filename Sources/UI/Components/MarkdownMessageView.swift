import Foundation
import SwiftUI

/// A small native Markdown renderer for assistant output. Foundation handles inline
/// CommonMark formatting, while block parsing gives fenced code, lists and headings
/// deliberate spacing and keeps long code out of the proportional body font.
public struct MarkdownMessageView: View {
    public let markdown: String

    public init(markdown: String) {
        self.markdown = markdown
    }

    private var blocks: [MarkdownBlock] { MarkdownBlock.parse(markdown) }

    public var body: some View {
        LazyVStack(alignment: .leading, spacing: 11) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            inlineText(text)
                .font(.system(size: 14))
                .lineSpacing(4)
                .textSelection(.enabled)

        case .heading(let text, let level):
            inlineText(text)
                .font(.system(size: headingSize(level), weight: .semibold))
                .foregroundStyle(CodexTheme.primaryText)
                .textSelection(.enabled)
                .padding(.top, level == 1 ? 6 : 2)

        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Circle()
                    .fill(CodexTheme.secondaryText)
                    .frame(width: 4, height: 4)
                    .padding(.leading, 3)
                inlineText(text)
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
            .padding(.leading, 12)

        case .numbered(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CodexTheme.secondaryText)
                    .frame(minWidth: 18, alignment: .trailing)
                inlineText(text)
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
            .padding(.leading, 7)

        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(CodexTheme.tertiaryText.opacity(0.7))
                    .frame(width: 2)
                inlineText(text)
                    .font(.system(size: 14))             // Increased (was 13.5)
                    .foregroundStyle(CodexTheme.secondaryText)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .code(let source, let language):
            CodeBlockView(code: source, language: language.isEmpty ? nil : language)
                .padding(.vertical, 2)

        case .divider:
            Rectangle()
                .fill(CodexTheme.border)
                .frame(height: 1)
                .padding(.vertical, 5)
        }
    }

    private func inlineText(_ source: String) -> Text {
        do {
            let styled = try AttributedString(
                markdown: source,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
            return Text(styled).foregroundColor(CodexTheme.primaryText)
        } catch {
            return Text(source).foregroundColor(CodexTheme.primaryText)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: 23      // Increased (was 21)
        case 2: 19      // Increased (was 18)
        case 3: 17      // Increased (was 16)
        default: 15.5   // Increased (was 14.5)
        }
    }
}

private enum MarkdownBlock {
    case paragraph(String)
    case heading(String, Int)
    case bullet(String)
    case numbered(Int, String)
    case quote(String)
    case code(String, String)
    case divider

    static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var codeLanguage = ""
        var insideCodeFence = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let joined = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            paragraph.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if insideCodeFence {
                    blocks.append(.code(codeLines.joined(separator: "\n"), codeLanguage))
                    codeLines.removeAll(keepingCapacity: true)
                    codeLanguage = ""
                    insideCodeFence = false
                } else {
                    flushParagraph()
                    insideCodeFence = true
                    codeLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                continue
            }

            if insideCodeFence {
                codeLines.append(line)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if let heading = headingParts(trimmed) {
                flushParagraph()
                blocks.append(.heading(heading.text, heading.level))
                continue
            }

            if isHorizontalRule(trimmed) {
                flushParagraph()
                blocks.append(.divider)
                continue
            }

            if trimmed.hasPrefix("> ") || trimmed == ">" {
                flushParagraph()
                blocks.append(.quote(String(trimmed.dropFirst(min(2, trimmed.count)))))
                continue
            }

            if let bullet = bulletText(trimmed) {
                flushParagraph()
                blocks.append(.bullet(bullet))
                continue
            }

            if let numbered = numberedText(trimmed) {
                flushParagraph()
                blocks.append(.numbered(numbered.number, numbered.text))
                continue
            }

            paragraph.append(line)
        }

        flushParagraph()
        if insideCodeFence {
            blocks.append(.code(codeLines.joined(separator: "\n"), codeLanguage))
        }
        return blocks
    }

    private static func headingParts(_ line: String) -> (level: Int, text: String)? {
        let count = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(count), line.dropFirst(count).first == " " else { return nil }
        return (count, String(line.dropFirst(count + 1)))
    }

    private static func bulletText(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func numberedText(_ line: String) -> (number: Int, text: String)? {
        guard let separator = line.firstIndex(where: { $0 == "." || $0 == ")" }),
              line.index(after: separator) < line.endIndex,
              line[line.index(after: separator)] == " ",
              let number = Int(line[..<separator]) else { return nil }
        return (number, String(line[line.index(separator, offsetBy: 2)...]))
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.filter { $0 != " " && $0 != "\t" }
        return ["---", "***", "___"].contains(compact)
    }
}
