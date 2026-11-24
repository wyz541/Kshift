import SwiftUI

enum MarkdownViewMode: String, CaseIterable, Identifiable {
    case source
    case preview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source: "源码"
        case .preview: "预览"
        }
    }
}

struct MarkdownEditorView: View {
    @Binding var text: String
    let mode: MarkdownViewMode
    var paneHeight: CGFloat = 220
    var showsBackground = true
    @FocusState private var isSourceFocused: Bool

    var body: some View {
        Group {
            switch mode {
            case .source:
                sourcePane
            case .preview:
                previewPane
            }
        }
        .frame(maxWidth: .infinity, minHeight: paneHeight, maxHeight: paneHeight)
        .background(
            .primary.opacity(showsBackground ? 0.025 : 0),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private var sourcePane: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .padding(8)
            .scrollContentBackground(.hidden)
            .writingToolsBehavior(.disabled)
            .focused($isSourceFocused)
            .overlay(alignment: .topLeading) {
                if Self.shouldShowPlaceholder(for: text, isFocused: isSourceFocused) {
                    Text("输入 Markdown")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(showsBackground ? .tertiary : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel("Markdown 源码")
            .accessibilityIdentifier("markdown-editor")
    }

    static func shouldShowPlaceholder(for text: String, isFocused: Bool) -> Bool {
        text.isEmpty && !isFocused
    }

    private var previewPane: some View {
        ScrollView {
            KshiftMarkdownText(
                source: text.isEmpty ? "暂无内容" : text,
                isPlaceholder: text.isEmpty
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(14)
        }
        .accessibilityLabel("Markdown 预览")
        .accessibilityIdentifier("markdown-preview")
    }
}

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case numbered(String, String)
    case quote(String)
    case code(String)
    case divider
}

enum MarkdownBlockParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String] = []
        var isInCodeBlock = false

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
            paragraphLines.removeAll()
        }

        for rawLine in source.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if isInCodeBlock {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                } else {
                    flushParagraph()
                }
                isInCodeBlock.toggle()
                continue
            }
            if isInCodeBlock {
                codeLines.append(rawLine)
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            if trimmed == "---" || trimmed == "***" {
                flushParagraph()
                blocks.append(.divider)
                continue
            }
            if let heading = parseHeading(trimmed) {
                flushParagraph()
                blocks.append(heading)
                continue
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushParagraph()
                blocks.append(.bullet(String(trimmed.dropFirst(2))))
                continue
            }
            if let numbered = parseNumbered(trimmed) {
                flushParagraph()
                blocks.append(numbered)
                continue
            }
            if trimmed.hasPrefix("> ") {
                flushParagraph()
                blocks.append(.quote(String(trimmed.dropFirst(2))))
                continue
            }
            paragraphLines.append(trimmed)
        }
        flushParagraph()
        if isInCodeBlock, !codeLines.isEmpty {
            blocks.append(.code(codeLines.joined(separator: "\n")))
        }
        return blocks
    }

    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        let level = line.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else { return nil }
        let content = line.dropFirst(level)
        guard content.first == " " else { return nil }
        return .heading(
            level: level,
            text: String(content.dropFirst()).trimmingCharacters(in: .whitespaces)
        )
    }

    private static func parseNumbered(_ line: String) -> MarkdownBlock? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let number = String(line[..<dot])
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        let remainder = line[line.index(after: dot)...]
        guard remainder.first == " " else { return nil }
        return .numbered(number, String(remainder.dropFirst()))
    }
}

struct KshiftMarkdownText: View {
    let source: String
    var isPlaceholder = false

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isPlaceholder || blocks.isEmpty {
                Text(source.isEmpty ? "暂无内容" : source)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            inlineText(text)
                .font(headingFont(level))
                .fontWeight(.bold)
        case let .paragraph(text):
            inlineText(text)
        case let .bullet(text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                inlineText(text)
            }
        case let .numbered(number, text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).")
                    .monospacedDigit()
                inlineText(text)
            }
        case let .quote(text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.tint)
                    .frame(width: 3)
                inlineText(text)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        case let .code(code):
            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .kshiftContentBoard()
        case .divider:
            Divider()
        }
    }

    private func inlineText(_ source: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: source,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return Text(attributed)
        }
        return Text(source)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title
        case 2: .title2
        case 3: .title3
        default: .headline
        }
    }
}
