import SwiftUI
import SwiftMath

final class RenderedMath {
    let image: NSImage
    /// Distance the formula extends below its baseline; used to align inline math with the text.
    let descent: CGFloat

    init(image: NSImage, descent: CGFloat) {
        self.image = image
        self.descent = descent
    }
}

/// Typesets LaTeX with SwiftMath (CoreText, no web view or JavaScript) into images.
/// The ink colour is resolved from the system label colour for the given colour
/// scheme, so formulas follow Light and Dark Mode like the surrounding text.
enum MathRenderer {
    private static let cache = NSCache<NSString, RenderedMath>()

    /// Returns nil when the LaTeX can't be parsed.
    static func render(_ latex: String, fontSize: CGFloat, display: Bool, scheme: ColorScheme) -> RenderedMath? {
        let key = "\(scheme == .dark ? "dark" : "light")|\(fontSize)|\(display)|\(latex)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        var math = MathImage(
            latex: normalize(latex),
            fontSize: fontSize,
            textColor: labelColor(for: scheme),
            labelMode: display ? .display : .text,
            textAlignment: .left
        )
        let (error, image, layout) = math.asImage()
        guard error == nil, let image, let layout else { return nil }

        let rendered = RenderedMath(image: image, descent: layout.descent)
        cache.setObject(rendered, forKey: key)
        return rendered
    }

    /// SwiftMath covers most of KaTeX but spells a few common constructs differently
    /// (or not at all). Map those onto equivalents it understands.
    private static let normalizations: [(pattern: String, template: String)] = [
        (#"\\[dt]frac(?![A-Za-z])"#, #"\\frac"#),
        (#"\\operatorname\*?\{"#, #"\\mathrm{"#),
        (#"\\implies(?![A-Za-z])"#, #"\\Longrightarrow "#),
        (#"\\iff(?![A-Za-z])"#, #"\\Longleftrightarrow "#),
        (#"\\boldsymbol(?![A-Za-z])"#, #"\\mathbf"#),
        (#"\\begin\{(?:align|alignat|flalign|eqnarray|gather)\*?\}(\{[0-9]+\})?"#, #"\\begin{aligned}"#),
        (#"\\end\{(?:align|alignat|flalign|eqnarray|gather)\*?\}"#, #"\\end{aligned}"#),
        (#"\\(?:begin|end)\{equation\*?\}"#, ""),
        (#"\\begin\{array\}\{[^}]*\}"#, #"\\begin{matrix}"#),
        (#"\\end\{array\}"#, #"\\end{matrix}"#),
        (#"\\tag\*?\{[^}]*\}"#, ""),
        (#"\\!"#, ""),
    ]

    static func normalize(_ latex: String) -> String {
        var result = latex
        for (pattern, template) in normalizations {
            result = result.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func labelColor(for scheme: ColorScheme) -> NSColor {
        var color = NSColor.labelColor
        NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            color = NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor
        }
        return color
    }
}
