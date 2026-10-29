import SwiftUI
import WebKit

@main struct PlainWalkApp: App {
    var body: some Scene {
        WindowGroup { LocalWebApp().ignoresSafeArea().onOpenURL { _ in } }
    }
}
struct LocalWebApp: UIViewRepresentable {
    func makeCoordinator() -> NativeBridge { NativeBridge() }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.setURLSchemeHandler(AssetSchemeHandler(), forURLScheme: "plainwalk-local")
        configuration.userContentController.addUserScript(WKUserScript(source: NativeBridge.bootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.add(context.coordinator, name: "plainwalk")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator; web.uiDelegate = context.coordinator; context.coordinator.webView = web
        web.isOpaque = false; web.backgroundColor = .systemBackground; web.scrollView.backgroundColor = .systemBackground
        web.scrollView.isScrollEnabled = false; web.scrollView.contentInsetAdjustmentBehavior = .never
        web.allowsBackForwardNavigationGestures = false
        #if DEBUG
        web.isInspectable = true
        #endif
        web.load(URLRequest(url: URL(string: "plainwalk-local://app/index.html")!))
        return web
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
