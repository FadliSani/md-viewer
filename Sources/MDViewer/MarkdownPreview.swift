import SwiftUI

/// The rendered side of the split view. Every `Text` inside is selectable, so the
/// standard macOS context menu (Copy, Look Up, Translate, Share…) works on it.
struct PreviewPane: View {
    let markdown: String

    private static let readingWidth: CGFloat = 760

    var body: some View {
        let blocks = MarkdownParser.parse(markdown)
        Group {
            if blocks.isEmpty {
                ContentUnavailableView(
                    "Nothing to Preview",
                    systemImage: "doc.text",
                    description: Text("Start typing Markdown in the editor.")
                )
            } else {
                ScrollView {
                    // A centred reading column keeps line lengths comfortable in wide windows.
                    MarkdownBlocksView(blocks: blocks)
                        .frame(maxWidth: Self.readingWidth, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                        .textSelection(.enabled)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - Blocks

struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]
    var spacing: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(blocks.indices, id: \.self) { index in
                MarkdownBlockView(block: blocks[index])
            }
        }
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case let .heading(level, text):
            VStack(alignment: .leading, spacing: 6) {
                InlineText(text, fontSize: Self.headingSize(level))
                    .font(Self.headingFont(level))
                    .fontWeight(level <= 4 ? .semibold : nil)
                    .foregroundStyle(level == 6 ? Color.secondary : Color.primary)
                if level <= 2 {
                    Divider()
                }
            }
            .padding(.top, level <= 2 ? 6 : 2)

        case let .paragraph(text):
            InlineText(text)
                .lineSpacing(2)

        case let .math(latex):
            MathBlockView(latex: latex)

        case let .mermaid(source):
            MermaidView(source: source)

        case let .code(_, text):
            ScrollView(.horizontal) {
                Text(verbatim: text)
                    .font(.system(.callout, design: .monospaced))
                    .padding(12)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(nsColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 8))

        case let .quote(blocks):
            MarkdownBlocksView(blocks: blocks, spacing: 8)
                .foregroundStyle(.secondary)
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(nsColor: .separatorColor))
                        .frame(width: 3)
                }

        case let .list(list):
            MarkdownListView(list: list)

        case let .table(table):
            MarkdownTableView(table: table)

        case .rule:
            Divider()
        }
    }

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .largeTitle
        case 2: .title
        case 3: .title2
        case 4: .title3
        case 5: .headline
        default: .subheadline
        }
    }

    /// Point sizes of the fonts above on macOS, so inline math matches its heading.
    private static func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: 26
        case 2: 22
        case 3: 17
        case 4: 15
        case 5: 13
        default: 11
        }
    }
}

// MARK: - Lists

private struct MarkdownListView: View {
    let list: MarkdownList

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(list.items.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    marker(for: list.items[index], number: list.start + index)
                        .frame(minWidth: 20, alignment: .trailing)
                        .textSelection(.disabled)
                    MarkdownBlocksView(blocks: list.items[index].blocks, spacing: 6)
                }
            }
        }
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func marker(for item: MarkdownList.Item, number: Int) -> some View {
        if let done = item.task {
            Image(systemName: done ? "checkmark.square.fill" : "square")
                .foregroundStyle(done ? Color.accentColor : Color.secondary)
        } else if list.ordered {
            Text("\(number).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } else {
            Text("•")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Tables

private struct MarkdownTableView: View {
    let table: MarkdownTable

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(table.header.indices, id: \.self) { column in
                        cell(table.header[column], column: column, isHeader: true)
                    }
                }
                ForEach(table.rows.indices, id: \.self) { row in
                    Divider()
                    GridRow {
                        ForEach(table.rows[row].indices, id: \.self) { column in
                            cell(table.rows[row][column], column: column, isHeader: false)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func cell(_ text: String, column: Int, isHeader: Bool) -> some View {
        let alignment = table.alignments[column]
        return InlineText(text)
            .fontWeight(isHeader ? .semibold : nil)
            .multilineTextAlignment(Self.textAlignment(alignment))
            .frame(maxWidth: .infinity, alignment: Self.frameAlignment(alignment))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isHeader ? Color(nsColor: .quaternarySystemFill) : Color.clear)
    }

    private static func frameAlignment(_ alignment: MarkdownTable.Alignment) -> Alignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private static func textAlignment(_ alignment: MarkdownTable.Alignment) -> TextAlignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

// MARK: - Inline

enum MarkdownInline {
    /// Resolves inline Markdown. Code spans get a subtle system fill behind them.
    static func attributed(_ source: String) -> AttributedString {
        let parsed = (try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(source)

        var result = parsed
        for run in parsed.runs where run.inlinePresentationIntent?.contains(.code) == true {
            result[run.range].backgroundColor = Color(nsColor: .quaternarySystemFill)
        }
        return result
    }

    /// Inline Markdown plus LaTeX. Each `$…$` span is typeset to an image and placed
    /// in the text flow, sitting on the surrounding baseline.
    static func text(_ source: String, fontSize: CGFloat, scheme: ColorScheme) -> Text {
        let (masked, spans) = MarkdownMath.mask(source)
        let attributed = attributed(masked)
        guard !spans.isEmpty else { return Text(attributed) }

        var result = Text(verbatim: "")
        var nextSpan = 0
        var segmentStart = attributed.startIndex
        var index = attributed.startIndex
        while index < attributed.endIndex {
            let next = attributed.characters.index(after: index)
            if attributed.characters[index] == MarkdownMath.placeholder, nextSpan < spans.count {
                if segmentStart < index {
                    result = result + Text(AttributedString(attributed[segmentStart..<index]))
                }
                result = result + mathText(spans[nextSpan], fontSize: fontSize, scheme: scheme)
                nextSpan += 1
                segmentStart = next
            }
            index = next
        }
        if segmentStart < attributed.endIndex {
            result = result + Text(AttributedString(attributed[segmentStart...]))
        }
        return result
    }

    private static func mathText(_ span: MarkdownMath.Span, fontSize: CGFloat, scheme: ColorScheme) -> Text {
        let size = span.display ? fontSize * 1.2 : fontSize
        guard let math = MathRenderer.render(span.latex, fontSize: size, display: span.display, scheme: scheme) else {
            // Like KaTeX, show invalid LaTeX as its red source rather than dropping it.
            let delimiter = span.display ? "$$" : "$"
            return Text(verbatim: delimiter + span.latex + delimiter)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Color.red)
        }
        return Text(Image(nsImage: math.image)).baselineOffset(-math.descent)
    }
}

/// A line of inline Markdown (with LaTeX) that re-typesets when the appearance changes.
struct InlineText: View {
    let source: String
    let fontSize: CGFloat
    @Environment(\.colorScheme) private var scheme

    init(_ source: String, fontSize: CGFloat = 13) {
        self.source = source
        self.fontSize = fontSize
    }

    var body: some View {
        MarkdownInline.text(source, fontSize: fontSize, scheme: scheme)
    }
}

// MARK: - Display math

private struct MathBlockView: View {
    let latex: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let math = MathRenderer.render(latex, fontSize: 20, display: true, scheme: scheme) {
                // Centred when it fits, scrolls sideways when it doesn't.
                ViewThatFits(in: .horizontal) {
                    Image(nsImage: math.image)
                        .frame(maxWidth: .infinity)
                    ScrollView(.horizontal) {
                        Image(nsImage: math.image)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .accessibilityLabel(latex)
                .contextMenu {
                    Button("Copy LaTeX") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(latex, forType: .string)
                    }
                }
            } else {
                Text(verbatim: latex)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }
}
