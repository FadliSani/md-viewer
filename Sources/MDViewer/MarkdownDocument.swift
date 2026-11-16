import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Support/Info.plist so the Open/Save panels filter on .md files.
    static let markdownText = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.markdownText] }
    static var writableContentTypes: [UTType] { [.markdownText] }

    var text: String

    init(text: String = MarkdownDocument.welcomeText) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }

    static let welcomeText = """
    # Welcome to MD Viewer

    Write Markdown on the left and see it **rendered** on the right. Drag the divider to resize the panes.

    ## What you can do

    - Select any text in the preview, then Control-click and choose *Look Up*
    - Open and save `.md` files with the standard macOS panels
    - Follow Light and Dark Mode automatically

    1. Headings, lists, and task lists
    2. [Links](https://www.apple.com) and `inline code`
    3. Block quotes, tables, and fenced code

    - [x] Render Markdown
    - [ ] Write something great

    > Simplicity is the ultimate sophistication.

    ## Math

    Inline math like $E = mc^2$ sits in the text, and display math gets its own line:

    $$
    \\int_{-\\infty}^{\\infty} e^{-x^2}\\,dx = \\sqrt{\\pi}
    $$

    ```swift
    let greeting = "Hello, Markdown"
    print(greeting)
    ```

    ```mermaid
    flowchart LR
      Write --> Preview --> Share
    ```

    | Shortcut | Action |
    | :------- | -----: |
    | ⌘O       | Open   |
    | ⌘S       | Save   |
    """
}
