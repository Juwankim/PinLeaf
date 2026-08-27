//
//  FloatingMarkdownPreview.swift
//  PinLeaf
//

import SwiftUI

struct FloatingMarkdownPreview: View {
    let markdown: String
    let zoomScale: Double

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(markdown)
    }

    var body: some View {
        ScrollView {
            if blocks.isEmpty {
                Text("미리 볼 내용이 없습니다.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVStack(alignment: .leading, spacing: 10 * zoomScale) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.38))
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, content):
            Text(inlineMarkdown(content))
                .font(.system(size: headingSize(for: level) * zoomScale, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)

        case let .paragraph(content):
            Text(inlineMarkdown(content))
                .font(.system(size: 14 * zoomScale))
                .lineSpacing(3 * zoomScale)
                .frame(maxWidth: .infinity, alignment: .leading)

        case let .list(ordered, items):
            VStack(alignment: .leading, spacing: 5 * zoomScale) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .font(.system(size: 14 * zoomScale, weight: .semibold))
                            .frame(minWidth: ordered ? 20 : 10, alignment: .trailing)

                        Text(inlineMarkdown(item))
                            .font(.system(size: 14 * zoomScale))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case let .quote(content):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.primary.opacity(0.28))
                    .frame(width: 3)

                Text(inlineMarkdown(content))
                    .font(.system(size: 14 * zoomScale).italic())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case let .code(content):
            ScrollView(.horizontal) {
                Text(content)
                    .font(.system(size: 12.5 * zoomScale, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(Color.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))

        case .divider:
            Divider()
        }
    }

    private func inlineMarkdown(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: source, options: options))
            ?? AttributedString(source)
    }

    private func headingSize(for level: Int) -> CGFloat {
        switch level {
        case 1: 21
        case 2: 18
        case 3: 16
        case 4: 14
        default: 14
        }
    }
}

private enum MarkdownBlock {
    case heading(level: Int, content: String)
    case paragraph(String)
    case list(ordered: Bool, items: [String])
    case quote(String)
    case code(String)
    case divider
}

private enum MarkdownBlockParser {
    private enum PendingBlock {
        case paragraph([String])
        case list(ordered: Bool, items: [String])
        case quote([String])
    }

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var pending: PendingBlock?
        var codeLines: [String] = []
        var isInsideCodeFence = false

        for rawLine in markdown.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if isInsideCodeFence {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines.removeAll(keepingCapacity: true)
                } else {
                    flush(&pending, into: &blocks)
                }
                isInsideCodeFence.toggle()
                continue
            }

            if isInsideCodeFence {
                codeLines.append(rawLine)
                continue
            }

            if trimmed.isEmpty {
                flush(&pending, into: &blocks)
                continue
            }

            if let heading = heading(from: trimmed) {
                flush(&pending, into: &blocks)
                blocks.append(.heading(level: heading.level, content: heading.content))
                continue
            }

            if isDivider(trimmed) {
                flush(&pending, into: &blocks)
                blocks.append(.divider)
                continue
            }

            if let item = unorderedListItem(from: trimmed) {
                appendListItem(item, ordered: false, pending: &pending, blocks: &blocks)
                continue
            }

            if let item = orderedListItem(from: trimmed) {
                appendListItem(item, ordered: true, pending: &pending, blocks: &blocks)
                continue
            }

            if trimmed.hasPrefix(">") {
                let quote = String(trimmed.dropFirst())
                    .trimmingCharacters(in: .whitespaces)
                appendQuoteLine(quote, pending: &pending, blocks: &blocks)
                continue
            }

            appendParagraphLine(rawLine, pending: &pending, blocks: &blocks)
        }

        if isInsideCodeFence {
            blocks.append(.code(codeLines.joined(separator: "\n")))
        }
        flush(&pending, into: &blocks)
        return blocks
    }

    private static func heading(from line: String) -> (level: Int, content: String)? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level) else { return nil }
        let remainder = line.dropFirst(level)
        guard remainder.first?.isWhitespace == true else { return nil }
        return (level, remainder.trimmingCharacters(in: .whitespaces))
    }

    private static func isDivider(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let marker = compact.first else { return false }
        guard marker == "-" || marker == "*" || marker == "_" else { return false }
        return compact.allSatisfy { $0 == marker }
    }

    private static func unorderedListItem(from line: String) -> String? {
        for prefix in ["- ", "* ", "+ ", "• "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }

    private static func orderedListItem(from line: String) -> String? {
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }
        let number = line[..<dotIndex]
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }

        let contentStart = line.index(after: dotIndex)
        guard contentStart < line.endIndex, line[contentStart].isWhitespace else { return nil }
        return String(line[contentStart...]).trimmingCharacters(in: .whitespaces)
    }

    private static func appendListItem(
        _ item: String,
        ordered: Bool,
        pending: inout PendingBlock?,
        blocks: inout [MarkdownBlock]
    ) {
        if case let .list(existingOrder, items) = pending, existingOrder == ordered {
            pending = .list(ordered: ordered, items: items + [item])
        } else {
            flush(&pending, into: &blocks)
            pending = .list(ordered: ordered, items: [item])
        }
    }

    private static func appendQuoteLine(
        _ line: String,
        pending: inout PendingBlock?,
        blocks: inout [MarkdownBlock]
    ) {
        if case let .quote(lines) = pending {
            pending = .quote(lines + [line])
        } else {
            flush(&pending, into: &blocks)
            pending = .quote([line])
        }
    }

    private static func appendParagraphLine(
        _ line: String,
        pending: inout PendingBlock?,
        blocks: inout [MarkdownBlock]
    ) {
        if case let .paragraph(lines) = pending {
            pending = .paragraph(lines + [line])
        } else {
            flush(&pending, into: &blocks)
            pending = .paragraph([line])
        }
    }

    private static func flush(
        _ pending: inout PendingBlock?,
        into blocks: inout [MarkdownBlock]
    ) {
        guard let block = pending else { return }

        switch block {
        case let .paragraph(lines):
            blocks.append(.paragraph(lines.joined(separator: "\n")))
        case let .list(ordered, items):
            blocks.append(.list(ordered: ordered, items: items))
        case let .quote(lines):
            blocks.append(.quote(lines.joined(separator: "\n")))
        }

        pending = nil
    }
}
