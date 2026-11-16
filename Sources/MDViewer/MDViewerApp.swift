import SwiftUI

@main
struct MDViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // DocumentGroup provides the native Open / Save / Save As panels, recent
        // documents, autosave, and the dirty-state indicator in the title bar.
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .defaultSize(width: 900, height: 700)
        .defaultLaunchBehavior(.suppressed)
        .commands { EditorCommands() }
    }
}

private struct EditorCommands: Commands {
    @FocusedBinding(\.isEditing) private var isEditing: Bool?

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Toggle("Edit Markdown", isOn: Binding(get: { isEditing ?? false }, set: { isEditing = $0 }))
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(isEditing == nil)
        }
    }
}

/// Like TextEdit, launching the app on its own (Dock, Spotlight, Finder's app
/// icon) shows an Open dialog with a "New Document" button, rather than a blank
/// window. Opening a file from Finder skips the dialog and shows just that file.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var launchPanel: NSOpenPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Finder's open-file events arrive around launch; give them a moment so a
        // file opened from the context menu doesn't also trigger the dialog.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            if !hasOpenWindows { presentLaunchPanel() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { presentLaunchPanel() }
        return false
    }

    private var hasOpenWindows: Bool {
        !NSDocumentController.shared.documents.isEmpty || NSApp.windows.contains { $0.isVisible }
    }

    private func presentLaunchPanel() {
        guard launchPanel?.isVisible != true else { return }

        let panel = NSOpenPanel()
        panel.message = "Choose a Markdown file to open, or create a new document."
        panel.allowedContentTypes = [.markdownText]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        let newButton = NSButton(title: "New Document", target: self, action: #selector(newDocument(_:)))
        newButton.bezelStyle = .rounded
        newButton.sizeToFit()
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: newButton.frame.width + 40, height: newButton.frame.height + 16))
        newButton.frame.origin = NSPoint(x: 20, y: 8)
        accessory.addSubview(newButton)
        panel.accessoryView = accessory
        panel.isAccessoryViewDisclosed = true

        launchPanel = panel
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            }
        }
    }

    @objc private func newDocument(_ sender: Any?) {
        launchPanel?.cancel(nil)
        NSDocumentController.shared.newDocument(nil)
    }
}
