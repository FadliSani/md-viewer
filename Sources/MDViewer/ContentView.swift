import SwiftUI

struct ContentView: View {
    @Binding var document: MarkdownDocument
    @StateObject private var window: WindowState

    init(document: Binding<MarkdownDocument>, fileURL: URL?) {
        _document = document
        // This is a viewer first: files opened from disk are shown rendered in
        // full. Only a brand-new, untitled document starts with the editor open.
        _window = StateObject(wrappedValue: WindowState(isEditing: fileURL == nil))
    }

    var body: some View {
        // HSplitView supplies the native, draggable divider between the panes.
        HSplitView {
            if window.isEditing {
                EditorPane(text: $document.text)
                    .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
            }
            PreviewPane(markdown: document.text)
                .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 420, minHeight: 320)
        .focusedSceneValue(\.isEditing, $window.isEditing)
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $window.isEditing) {
                    Label("Edit", systemImage: "square.and.pencil")
                }
                .help("Show or hide the Markdown editor")
            }
        }
    }
}

/// Per-window UI state. (An ObservableObject rather than @State, which needs a
/// compiler plugin that the Command Line Tools toolchain doesn't ship.)
private final class WindowState: ObservableObject {
    @Published var isEditing: Bool

    init(isEditing: Bool) {
        self.isEditing = isEditing
    }
}

private struct EditorPane: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .autocorrectionDisabled()
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - Menu bar access to the focused window's editor state

private struct IsEditingKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var isEditing: Binding<Bool>? {
        get { self[IsEditingKey.self] }
        set { self[IsEditingKey.self] = newValue }
    }
}
