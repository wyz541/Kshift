import SwiftUI

enum MarkdownEditorMode: String, CaseIterable, Identifiable {
    case write
    case preview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .write: "编写"
        case .preview: "预览"
        }
    }
}

struct MarkdownEditorView: View {
    @Binding var text: String
    var minimumHeight: CGFloat = 150

    @State private var mode: MarkdownEditorMode = .write

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Markdown mode", selection: $mode) {
                ForEach(MarkdownEditorMode.allCases) { mode in
                    Text(mode.title)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
            .accessibilityLabel("Markdown 编辑模式")
            .accessibilityIdentifier("markdown-mode")

            Group {
                switch mode {
                case .write:
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .writingToolsBehavior(.disabled)
                        .frame(minHeight: minimumHeight)
                        .kshiftContentBoard()
                        .accessibilityLabel("Markdown 编辑器")
                        .accessibilityIdentifier("markdown-editor")
                case .preview:
                    ScrollView {
                        KshiftMarkdownText(
                            source: text.isEmpty ? "暂无内容" : text,
                            isPlaceholder: text.isEmpty
                        )
                        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
                        .padding(12)
                    }
                    .kshiftContentBoard()
                    .accessibilityIdentifier("markdown-preview")
                }
            }
        }
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
