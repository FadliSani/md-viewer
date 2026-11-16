import SwiftUI
import WebKit

/// A ```mermaid block. Mermaid is JavaScript that needs a real browser layout
/// engine, so each diagram is a small WKWebView running the bundled mermaid.min.js
/// (MermaidAssets/, works offline). The web view is transparent so the diagram sits
/// on the preview's own background, and it follows Light and Dark Mode.
struct MermaidView: View {
    let source: String
    @Environment(\.colorScheme) private var scheme
    @StateObject private var model = MermaidModel()

    var body: some View {
        MermaidWebView(source: source, dark: scheme == .dark, model: model)
            .frame(height: model.height)
    }
}

/// Height of the rendered diagram, reported back by the page.
final class MermaidModel: ObservableObject {
    @Published var height: CGFloat = 80
}

private struct MermaidWebView: NSViewRepresentable {
    let source: String
    let dark: Bool
    let model: MermaidModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "size")

        let webView = DiagramWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground") // let the page background show through
        context.coordinator.webView = webView

        let assets = Bundle.module.url(forResource: "MermaidAssets", withExtension: nil)!
        webView.loadFileURL(assets.appendingPathComponent("index.html"), allowingReadAccessTo: assets)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.request(source: source, dark: dark)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "size")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let model: MermaidModel
        weak var webView: WKWebView?

        private var isLoaded = false
        private var requested: (source: String, dark: Bool)?
        private var debounce: DispatchWorkItem?

        init(model: MermaidModel) {
            self.model = model
        }

        /// Asks for a render. Edits are debounced so typing doesn't redraw on every
        /// keystroke; the first draw and appearance changes happen immediately.
        func request(source: String, dark: Bool) {
            if let requested, requested.source == source, requested.dark == dark { return }
            let immediate = requested == nil || requested?.source == source
            requested = (source, dark)

            debounce?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.flush() }
            debounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (immediate ? 0 : 0.3), execute: work)
        }

        private func flush() {
            guard isLoaded, let webView, let requested else { return }
            webView.callAsyncJavaScript(
                "await render(source, dark)",
                arguments: ["source": requested.source, "dark": requested.dark],
                in: nil,
                in: .page,
                completionHandler: nil
            )
        }

        // MARK: WKScriptMessageHandler

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let height = (message.body as? NSNumber)?.doubleValue else { return }
            let clamped = max(height, 24)
            if abs(model.height - clamped) > 0.5 { model.height = clamped }
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            flush()
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // Only the bundled page may load; links are handed to the default browser.
            if navigationAction.request.url?.isFileURL == true, navigationAction.navigationType == .other {
                decisionHandler(.allow)
                return
            }
            if let url = navigationAction.request.url, ["http", "https"].contains(url.scheme) {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }
}

/// Hands scrolling to the preview behind it (a web view would otherwise swallow the
/// wheel events) and trims browser-only items from its context menu, leaving
/// Copy, Look Up and the other text services.
private final class DiagramWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        let browserOnly: Set<String> = [
            "WKMenuItemIdentifierReload",
            "WKMenuItemIdentifierGoBack",
            "WKMenuItemIdentifierGoForward",
            "WKMenuItemIdentifierInspectElement",
        ]
        menu.items.removeAll { browserOnly.contains($0.identifier?.rawValue ?? "") }
    }
}
