import Foundation

// A small block-level Markdown parser. Inline syntax (bold, italic, links,
// code spans, strikethrough) is left in the strings and resolved at render time
// by Foundation's AttributedString(markdown:).

enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(language: String, text: String)
    case math(String)
    case mermaid(String)
    case quote([MarkdownBlock])
    case list(MarkdownList)
    case table(MarkdownTable)
    case rule
}

struct MarkdownList {
    var ordered: Bool
    var start: Int
    var items: [Item]

    struct Item {
        /// nil for a normal item, otherwise the state of a `[ ]` / `[x]` task.
        var task: Bool?
        var blocks: [MarkdownBlock]
    }
}

struct MarkdownTable {
    enum Alignment { case leading, center, trailing }

    var header: [String]
    var alignments: [Alignment]
    var rows: [[String]]
}

struct MarkdownParser {
    private let lines: [String]
    private var index = 0

    private init(lines: [String]) {
        self.lines = lines
    }

    static func parse(_ source: String) -> [MarkdownBlock] {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: "    ")
        var parser = MarkdownParser(lines: normalized.components(separatedBy: "\n"))
        return parser.parseBlocks()
    }

    // MARK: - Blocks

    private mutating func parseBlocks() -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        while index < lines.count {
            let line = lines[index]
            if Self.isBlank(line) {
                index += 1
            } else if let fence = Self.fence(line) {
                blocks.append(parseFence(fence))
            } else if let math = MarkdownMath.displayBlock(in: lines, at: index) {
                blocks.append(.math(math.latex))
                index = math.next
            } else if let heading = Self.heading(line) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
            } else if Self.isRule(line) {
                blocks.append(.rule)
                index += 1
            } else if Self.isQuote(line) {
                blocks.append(parseQuote())
            } else if Self.listMarker(line) != nil {
                blocks.append(parseList())
            } else if let table = parseTable() {
                blocks.append(table)
            } else {
                blocks.append(parseParagraph())
            }
        }
        return blocks
    }

    private mutating func parseFence(_ fence: Fence) -> MarkdownBlock {
        index += 1
        var body: [String] = []
        while index < lines.count {
            let line = lines[index]
            index += 1
            if let closing = Self.fence(line),
               closing.marker == fence.marker, closing.count >= fence.count, closing.info.isEmpty {
                break
            }
            body.append(String(line.dropFirst(min(fence.indent, Self.indentation(line)))))
        }
        let language = fence.info.split(separator: " ").first.map(String.init) ?? ""
        let text = body.joined(separator: "\n")
        switch language {
        case "math": return .math(text)
        case "mermaid": return .mermaid(text)
        default: return .code(language: language, text: text)
        }
    }

    private mutating func parseQuote() -> MarkdownBlock {
        var inner: [String] = []
        while index < lines.count {
            let line = lines[index]
            if Self.isQuote(line) {
                var content = line.drop(while: { $0 == " " }).dropFirst()
                if content.first == " " { content = content.dropFirst() }
                inner.append(String(content))
            } else if let last = inner.last, !Self.isBlank(last), !Self.isBlank(line), !Self.startsBlock(line) {
                inner.append(line) // lazy continuation
            } else {
                break
            }
            index += 1
        }
        var parser = MarkdownParser(lines: inner)
        return .quote(parser.parseBlocks())
    }

    private mutating func parseList() -> MarkdownBlock {
        let first = Self.listMarker(lines[index])!
        var items: [MarkdownList.Item] = []
        var previousOffset: Int?

        while index < lines.count,
              let marker = Self.listMarker(lines[index]),
              marker.ordered == first.ordered,
              previousOffset.map({ marker.indent < $0 }) ?? true {
            var content = [String(lines[index].dropFirst(marker.contentOffset))]
            index += 1
            var pendingBlanks = 0
            while index < lines.count {
                let line = lines[index]
                if Self.isBlank(line) {
                    pendingBlanks += 1
                } else if Self.indentation(line) >= marker.contentOffset {
                    content.append(contentsOf: Array(repeating: "", count: pendingBlanks))
                    content.append(String(line.dropFirst(marker.contentOffset)))
                    pendingBlanks = 0
                } else if pendingBlanks == 0, !Self.startsBlock(line) {
                    content.append(String(line.drop(while: { $0 == " " }))) // lazy continuation
                } else {
                    break
                }
                index += 1
            }

            var task: Bool?
            if let head = content.first {
                if head.hasPrefix("[ ] ") || head == "[ ]" {
                    task = false
                    content[0] = String(head.dropFirst(4))
                } else if head.hasPrefix("[x] ") || head.hasPrefix("[X] ") {
                    task = true
                    content[0] = String(head.dropFirst(4))
                }
            }

            var parser = MarkdownParser(lines: content)
            items.append(.init(task: task, blocks: parser.parseBlocks()))
            previousOffset = marker.contentOffset
        }
        return .list(MarkdownList(ordered: first.ordered, start: first.number, items: items))
    }

    /// A table starts at a header row whose next line is a delimiter row with the
    /// same number of cells. Returns that table's column alignments.
    private func tableAlignments(at start: Int) -> [MarkdownTable.Alignment]? {
        guard start + 1 < lines.count,
              lines[start].contains("|"),
              let alignments = Self.delimiterRow(lines[start + 1]),
              Self.splitRow(lines[start]).count == alignments.count
        else { return nil }
        return alignments
    }

    private mutating func parseTable() -> MarkdownBlock? {
        guard let alignments = tableAlignments(at: index) else { return nil }
        let header = Self.splitRow(lines[index])

        // Rows run until a blank line or another block, so a row that is still
        // being typed (no pipes yet) stays in the table.
        var rows: [[String]] = []
        var next = index + 2
        while next < lines.count, !Self.isBlank(lines[next]), !Self.startsBlock(lines[next]) {
            var cells = Self.splitRow(lines[next])
            if cells.count < header.count {
                cells += Array(repeating: "", count: header.count - cells.count)
            }
            rows.append(Array(cells.prefix(header.count)))
            next += 1
        }
        index = next
        return .table(MarkdownTable(header: header, alignments: alignments, rows: rows))
    }

    private mutating func parseParagraph() -> MarkdownBlock {
        var parts: [String] = []
        while index < lines.count {
            let line = lines[index]
            if Self.isBlank(line) { break }
            if !parts.isEmpty {
                if let level = Self.setextLevel(line) {
                    index += 1
                    return .heading(level: level, text: Self.joinSoftBreaks(parts))
                }
                if Self.interruptsParagraph(line) || tableAlignments(at: index) != nil
                    || MarkdownMath.displayBlock(in: lines, at: index) != nil { break }
            }
            parts.append(line)
            index += 1
        }
        return .paragraph(Self.joinSoftBreaks(parts))
    }

    // MARK: - Line classification

    private struct Fence {
        var marker: Character
        var count: Int
        var info: String
        var indent: Int
    }

    private struct ListMarker {
        var indent: Int
        var ordered: Bool
        var number: Int
        var contentOffset: Int
        var isEmpty: Bool
    }

    private enum Pattern {
        static let listMarker = try! NSRegularExpression(pattern: #"^( {0,3})([-*+]|\d{1,9}[.)])( +|$)"#)
        static let rule = #"^ {0,3}([-*_])( *\1){2,} *$"#
        static let setext = #"^ {0,3}(=+|-+) *$"#
        static let closingHashes = #"\s+#+$"#
        static let delimiterRow = #"^\|? *:?-+:? *(\| *:?-+:? *)*\|?$"#
    }

    private static func isBlank(_ line: String) -> Bool {
        line.allSatisfy { $0 == " " }
    }

    private static func indentation(_ line: String) -> Int {
        line.prefix(while: { $0 == " " }).count
    }

    private static func startsBlock(_ line: String) -> Bool {
        heading(line) != nil || fence(line) != nil || isRule(line) || isQuote(line) || listMarker(line) != nil
    }

    private static func interruptsParagraph(_ line: String) -> Bool {
        if heading(line) != nil || fence(line) != nil || isRule(line) || isQuote(line) { return true }
        guard let marker = listMarker(line), !marker.isEmpty else { return false }
        return !marker.ordered || marker.number == 1
    }

    private static func isQuote(_ line: String) -> Bool {
        indentation(line) <= 3 && line.drop(while: { $0 == " " }).first == ">"
    }

    private static func isRule(_ line: String) -> Bool {
        line.range(of: Pattern.rule, options: .regularExpression) != nil
    }

    private static func setextLevel(_ line: String) -> Int? {
        guard line.range(of: Pattern.setext, options: .regularExpression) != nil else { return nil }
        return line.drop(while: { $0 == " " }).first == "=" ? 1 : 2
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        guard indentation(line) <= 3 else { return nil }
        let trimmed = line.drop(while: { $0 == " " })
        let hashes = trimmed.prefix(while: { $0 == "#" })
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = trimmed.dropFirst(hashes.count)
        guard rest.isEmpty || rest.first == " " else { return nil }

        var text = rest.trimmingCharacters(in: .whitespaces)
        if let closing = text.range(of: Pattern.closingHashes, options: .regularExpression) {
            text.removeSubrange(closing)
        } else if text.allSatisfy({ $0 == "#" }) {
            text = ""
        }
        return (hashes.count, text)
    }

    private static func fence(_ line: String) -> Fence? {
        let indent = indentation(line)
        guard indent <= 3, let marker = line.dropFirst(indent).first, marker == "`" || marker == "~" else { return nil }
        let run = line.dropFirst(indent).prefix(while: { $0 == marker }).count
        guard run >= 3 else { return nil }
        let info = line.dropFirst(indent + run).trimmingCharacters(in: .whitespaces)
        if marker == "`", info.contains("`") { return nil }
        return Fence(marker: marker, count: run, info: info, indent: indent)
    }

    private static func listMarker(_ line: String) -> ListMarker? {
        let whole = NSRange(line.startIndex..., in: line)
        guard let match = Pattern.listMarker.firstMatch(in: line, range: whole) else { return nil }
        let text = line as NSString
        let indent = match.range(at: 1).length
        let marker = text.substring(with: match.range(at: 2))
        let spaces = match.range(at: 3).length
        let isEmpty = text.substring(from: match.range.upperBound).allSatisfy { $0 == " " }
        let ordered = marker.first?.isNumber == true
        let gap = (spaces == 0 || spaces > 4 || isEmpty) ? 1 : spaces
        return ListMarker(
            indent: indent,
            ordered: ordered,
            number: Int(marker.dropLast()) ?? 1,
            contentOffset: indent + marker.count + gap,
            isEmpty: isEmpty
        )
    }

    // MARK: - Tables

    private static func delimiterRow(_ line: String) -> [MarkdownTable.Alignment]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|"), trimmed.contains("-"),
              trimmed.range(of: Pattern.delimiterRow, options: .regularExpression) != nil
        else { return nil }
        return splitRow(trimmed).map { cell in
            switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
            case (true, true): return .center
            case (false, true): return .trailing
            default: return .leading
            }
        }
    }

    private static func splitRow(_ line: String) -> [String] {
        var row = line.trimmingCharacters(in: .whitespaces)
        if row.hasPrefix("|") { row.removeFirst() }
        if row.hasSuffix("|"), !row.hasSuffix("\\|") { row.removeLast() }
        return row
            .replacingOccurrences(of: "\\|", with: "\u{0}")
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: "\u{0}", with: "|").trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Paragraph text

    /// Joins wrapped source lines the way Markdown renders them: a soft break
    /// becomes a space, while trailing two spaces or a backslash force a line break.
    private static func joinSoftBreaks(_ parts: [String]) -> String {
        var result = ""
        for (offset, raw) in parts.enumerated() {
            let hardBreak = raw.hasSuffix("  ") || raw.hasSuffix("\\")
            var text = raw.drop(while: { $0 == " " }).trimmingCharacters(in: .whitespaces)
            if raw.hasSuffix("\\") { text.removeLast() }
            result += text
            if offset < parts.count - 1 { result += hardBreak ? "\n" : " " }
        }
        return result
    }
}
