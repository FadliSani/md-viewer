import Foundation

// Finds LaTeX in Markdown source: display blocks ($$…$$, \[…\]) at block level
// and inline spans ($…$, $$…$$, \(…\)) inside text. Foundation only, so it can be
// shared by the parser and the inline renderer.

enum MarkdownMath {
    /// Stands in for each inline math span while Markdown inline syntax is parsed,
    /// so `*`, `_` and friends inside formulas are not mistaken for emphasis.
    static let placeholder: Character = "\u{E000}"

    struct Span {
        var latex: String
        var display: Bool
    }

    // MARK: - Display blocks

    /// A display equation starting at `lines[start]`. It must be closed before the
    /// next blank line, and nothing but whitespace may follow the closing delimiter;
    /// otherwise the text is left to the paragraph / inline rules.
    static func displayBlock(in lines: [String], at start: Int) -> (latex: String, next: Int)? {
        let first = lines[start].trimmingCharacters(in: .whitespaces)
        for (open, close) in [("$$", "$$"), ("\\[", "\\]")] where first.hasPrefix(open) {
            let afterOpen = String(first.dropFirst(open.count))

            if let end = afterOpen.range(of: close) {
                let content = afterOpen[..<end.lowerBound].trimmingCharacters(in: .whitespaces)
                let rest = afterOpen[end.upperBound...].trimmingCharacters(in: .whitespaces)
                return rest.isEmpty && !content.isEmpty ? (content, start + 1) : nil
            }

            var body = [afterOpen]
            var index = start + 1
            while index < lines.count {
                let line = lines[index]
                if line.allSatisfy({ $0 == " " }) { return nil }
                if let end = line.range(of: close) {
                    guard line[end.upperBound...].allSatisfy({ $0 == " " }) else { return nil }
                    body.append(String(line[..<end.lowerBound]))
                    let latex = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    return latex.isEmpty ? nil : (latex, index + 1)
                }
                body.append(line)
                index += 1
            }
            return nil
        }
        return nil
    }

    // MARK: - Inline spans

    /// Replaces every inline math span in `source` with `placeholder`, returning the
    /// spans in order. Code spans and escaped dollars are left alone, and `$` only
    /// opens math when it hugs the formula (so "$5 and $6" stays plain text).
    static func mask(_ source: String) -> (text: String, spans: [Span]) {
        guard source.contains("$") || source.contains("\\(") else { return (source, []) }

        let c = Array(source)
        let n = c.count
        var out = ""
        var spans: [Span] = []
        var i = 0

        func find(_ a: Character, _ b: Character, from start: Int) -> Int? {
            var j = start
            while j + 1 < n {
                if c[j] == a, c[j + 1] == b { return j }
                j += c[j] == "\\" ? 2 : 1
            }
            return nil
        }

        func closingDollar(from start: Int) -> Int? {
            var j = start
            while j < n {
                if c[j] == "\\" { j += 2; continue }
                if c[j] == "$" {
                    if j + 1 < n, c[j + 1] == "$" { return nil }
                    if j > start, !c[j - 1].isWhitespace, j + 1 >= n || !c[j + 1].isNumber { return j }
                }
                j += 1
            }
            return nil
        }

        while i < n {
            let ch = c[i]

            if ch == "\\" {
                if i + 1 < n, c[i + 1] == "(", let end = find("\\", ")", from: i + 2), end > i + 2 {
                    spans.append(Span(latex: String(c[(i + 2)..<end]), display: false))
                    out.append(placeholder)
                    i = end + 2
                } else {
                    out.append(ch)
                    if i + 1 < n { out.append(c[i + 1]) }
                    i += 2
                }
                continue
            }

            if ch == "`" {
                var run = 0
                while i + run < n, c[i + run] == "`" { run += 1 }
                var j = i + run
                var end = i + run
                while j < n {
                    guard c[j] == "`" else { j += 1; continue }
                    var length = 0
                    while j + length < n, c[j + length] == "`" { length += 1 }
                    if length == run { end = j + length; break }
                    j += length
                }
                out.append(contentsOf: c[i..<end])
                i = end
                continue
            }

            if ch == "$" {
                if i + 1 < n, c[i + 1] == "$" {
                    if let end = find("$", "$", from: i + 2), end > i + 2 {
                        spans.append(Span(latex: String(c[(i + 2)..<end]), display: true))
                        out.append(placeholder)
                        i = end + 2
                    } else {
                        out.append("$$")
                        i += 2
                    }
                    continue
                }
                if i + 1 < n, !c[i + 1].isWhitespace, let end = closingDollar(from: i + 1) {
                    spans.append(Span(latex: String(c[(i + 1)..<end]), display: false))
                    out.append(placeholder)
                    i = end + 1
                    continue
                }
            }

            out.append(ch)
            i += 1
        }
        return (out, spans)
    }
}
