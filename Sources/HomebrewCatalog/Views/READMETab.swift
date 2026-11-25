import SwiftUI

struct READMETab: View {
    let item: any BrewItem
    /// Raw Markdown as fetched from GitHub.
    let content: String?
    let isLoading: Bool
    let error: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading README...")
                    .frame(maxWidth: .infinity)
                    .padding(40)
            } else if let error = error {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    title: "README Not Available",
                    message: error
                )
            } else if let content = content {
                MarkdownDocumentView(markdown: content)
            } else {
                EmptyStateView(
                    icon: "doc.text",
                    title: "No README",
                    message: "This package doesn't have a README available"
                )
            }
        }
    }
}

// MARK: - Native Markdown rendering

/// Renders README Markdown with SwiftUI text. Raw HTML in the README is stripped
/// rather than interpreted, so repository content can never run script inside
/// the app (the previous WKWebView pasted the README into an HTML page verbatim).
struct MarkdownDocumentView: View {
    let markdown: String

    var body: some View {
        let blocks = MarkdownBlockParser.parse(markdown)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        // README links come from the repository: only web links reach the system.
        .environment(\.openURL, OpenURLAction { url in
            ExternalLinkPolicy.isOpenable(url) ? .systemAction : .discarded
        })
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(headingFont(level))
                .padding(.top, level <= 2 ? 8 : 4)
        case .paragraph(let text):
            Text(inline(text))
                .font(.body)
        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .padding(10)
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        case .list(let items, let ordered):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .foregroundStyle(.secondary)
                        Text(inline(item))
                    }
                }
            }
            .padding(.leading, 8)
        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.quaternary)
                    .frame(width: 3)
                Text(inline(text))
                    .foregroundStyle(.secondary)
            }
        case .rule:
            Divider()
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title.bold()
        case 2: return .title2.bold()
        case 3: return .title3.bold()
        default: return .headline
        }
    }

    /// Inline emphasis, code and links via Foundation's Markdown parser.
    private func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(String)
    case list([String], ordered: Bool)
    case quote(String)
    case rule
}

/// Line-based parser for the block structure READMEs actually use: headings,
/// paragraphs, fenced code, bullet/numbered lists, quotes and rules.
enum MarkdownBlockParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var listItems: [String] = []
        var listOrdered = false
        var quoteLines: [String] = []
        var codeLines: [String]? = nil

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }
        func flushList() {
            if !listItems.isEmpty {
                blocks.append(.list(listItems, ordered: listOrdered))
                listItems = []
            }
        }
        func flushQuote() {
            if !quoteLines.isEmpty {
                blocks.append(.quote(quoteLines.joined(separator: " ")))
                quoteLines = []
            }
        }
        func flushAll() {
            flushParagraph()
            flushList()
            flushQuote()
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            // Inside a fenced block everything is literal until the closing fence.
            if codeLines != nil {
                if rawLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    blocks.append(.code((codeLines ?? []).joined(separator: "\n")))
                    codeLines = nil
                } else {
                    codeLines?.append(rawLine)
                }
                continue
            }

            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                flushAll()
                codeLines = []
                continue
            }
            if line.isEmpty {
                flushAll()
                continue
            }
            if let heading = parseHeading(line) {
                flushAll()
                blocks.append(heading)
                continue
            }
            if line == "---" || line == "***" || line == "___" {
                flushAll()
                blocks.append(.rule)
                continue
            }
            if line.hasPrefix(">") {
                flushParagraph()
                flushList()
                quoteLines.append(stripHTML(String(line.dropFirst())))
                continue
            }
            if let (item, ordered) = parseListItem(line) {
                flushParagraph()
                flushQuote()
                if !listItems.isEmpty && ordered != listOrdered {
                    flushList()
                }
                listOrdered = ordered
                listItems.append(item)
                continue
            }

            let text = stripHTML(line)
            // A line that was only HTML (e.g. `<p align="center">`) renders as nothing.
            guard !text.isEmpty else { continue }
            flushList()
            flushQuote()
            paragraph.append(text)
        }

        if let code = codeLines {
            blocks.append(.code(code.joined(separator: "\n")))
        }
        flushAll()
        return blocks
    }

    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        let hashes = line.prefix(while: { $0 == "#" })
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.first == " " else { return nil }
        let text = stripHTML(String(rest))
        guard !text.isEmpty else { return nil }
        return .heading(level: hashes.count, text: text)
    }

    private static func parseListItem(_ line: String) -> (String, Bool)? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return (stripHTML(String(line.dropFirst(marker.count))), false)
        }
        // "1. item" or "1) item" — but not "1.2.3 release notes".
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return nil }
        var index = line.index(line.startIndex, offsetBy: digits.count)
        guard index < line.endIndex, line[index] == "." || line[index] == ")" else { return nil }
        index = line.index(after: index)
        guard index < line.endIndex, line[index] == " " else { return nil }
        return (stripHTML(String(line[index...])), true)
    }

    /// Removes HTML tags (and the body of script/style elements); other text between tags is kept.
    private static func stripHTML(_ text: String) -> String {
        text.replacingOccurrences(
            of: "<(script|style)[^>]*>.*?</\\1>", with: "",
            options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
