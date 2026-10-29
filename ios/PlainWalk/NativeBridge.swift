import SwiftUI
import WebKit
import UniformTypeIdentifiers
import MapKit

@MainActor final class NativeBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, UIDocumentPickerDelegate {
    weak var webView: WKWebView?
    let recorder = LocationRecorder()
    let health = HealthService()
    let activities = LiveActivityService()
    private var restoreReply: String?
    private var exportURLs: [URL] = []
    static let bootstrap = #"""
    (()=>{let counter=0;const pending=new Map();window.PlainWalkNative={
      request(action,payload={}){return new Promise((resolve,reject)=>{const id=String(++counter);const timeout=setTimeout(()=>{pending.delete(id);reject(Error('iOS の操作がタイムアウトしました。'))},120000);pending.set(id,{resolve,reject,timeout});window.webkit.messageHandlers.plainwalk.postMessage({id,action,payload})})},
      receive(message){if(message.id){const item=pending.get(message.id);if(!item)return;clearTimeout(item.timeout);pending.delete(message.id);message.error?item.reject(Error(message.error)):item.resolve(message.result)}else window.dispatchEvent(new CustomEvent('plainwalk-native',{detail:message}))}
    };})();
    """#
    override init() {
        super.init()
        recorder.onPoint = { [weak self] point, sessionID in
            self?.emit(["event": "location", "point": point.json, "sessionID": sessionID.map { $0 as Any } ?? NSNull()])
        }
        recorder.onError = { [weak self] text in self?.emit(["event": "error", "message": text]) }
        recorder.onSession = { [weak self] session in self?.activities.update(session) }
        activities.update(recorder.session)
        NotificationCenter.default.addObserver(self, selector: #selector(foreground), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    @objc private func foreground() { emit(["event": "foreground"]) }
    private func emit(_ message: [String: Any]) {
        webView?.callAsyncJavaScript("window.PlainWalkNative.receive(message)", arguments: ["message": message], in: nil, in: .page, completionHandler: nil)
    }
    private func reply(_ id: String, result: Any = NSNull(), error: String? = nil) {
        if let error { emit(["id": id, "error": error]) } else { emit(["id": id, "result": result]) }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              message.frameInfo.request.url?.scheme == "plainwalk-local",
              let body = message.body as? [String: Any], let id = body["id"] as? String,
              let action = body["action"] as? String else { return }
        let payload = body["payload"] as? [String: Any] ?? [:]
        Task { @MainActor in
            do {
                switch action {
                case "storageRead", "storageWrite":
                    guard let key = payload["key"] as? String, ["library", "active", "config"].contains(key) else { throw NativeError.message("保存先が不正です。") }
                    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PlainWalk", isDirectory: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let file = folder.appendingPathComponent("web-" + key + ".json")
                    if action == "storageRead" {
                        if let bytes = try? Data(contentsOf: file) { reply(id, result: try JSONSerialization.jsonObject(with: bytes, options: .fragmentsAllowed)) }
                        else { reply(id) }
                    } else {
                        let bytes = try JSONSerialization.data(withJSONObject: payload["value"] ?? NSNull(), options: .fragmentsAllowed)
                        try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]); reply(id)
                    }
                case "status": reply(id, result: ["session": recorder.session.map { $0.json as Any } ?? NSNull(), "healthAvailable": true, "version": 1])
                case "locationStart":
                    try recorder.start(id: payload["sessionID"] as? String, start: payload["start"] as? Double, recording: payload["recording"] as? Bool ?? false)
                    reply(id)
                case "locationStop": try recorder.stop(end: payload["end"] as? Bool ?? false); reply(id)
                case "photoCutout":
                    guard let encoded = payload["base64"] as? String, encoded.utf8.count < 8_000_000, let bytes = Data(base64Encoded: encoded) else { throw NativeError.message("切り抜く写真を読み取れません。") }
                    let output = try await CutoutService.cutout(bytes)
                    reply(id, result: "data:image/png;base64," + output.base64EncodedString())
                case "healthSteps": let total = try await health.steps(); reply(id, result: ["steps": total.map { $0 as Any } ?? NSNull()])
                case "healthWorkouts": reply(id, result: try await health.workouts())
                case "healthRoute": reply(id, result: try await health.route(id: payload["id"] as? String ?? ""))
                case "haptic": UIImpactFeedbackGenerator(style: .light).impactOccurred(); reply(id)
                case "shareFile":
                    guard let encoded = payload["base64"] as? String, encoded.utf8.count < 80_000_000,
                          let bytes = Data(base64Encoded: encoded) else { throw NativeError.message("書き出すファイルを読み取れません。") }
                    let proposed = (payload["name"] as? String ?? "plainwalk.json").replacingOccurrences(of: "/", with: "_")
                    let name = ["", ".", ".."].contains(proposed) ? "plainwalk-export.json" : proposed
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let url = folder.appendingPathComponent(name)
                    try bytes.write(to: url, options: .atomic); exportURLs.append(folder)
                    let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    controller.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: folder) }
                    present(controller); reply(id)
                case "restoreFile":
                    guard restoreReply == nil else { throw NativeError.message("ファイル選択をすでに開いています。") }
                    restoreReply = id
                    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
                    picker.delegate = self; picker.allowsMultipleSelection = false; present(picker)
                case "showMap":
                    let points = payload["points"] as? [[String: Any]] ?? []
                    present(NativeMapController(points: points, satellite: payload["satellite"] as? Bool ?? false)); reply(id)
                default: throw NativeError.message("対応していない iOS 操作です。")
                }
            } catch { reply(id, error: error.localizedDescription) }
        }
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        if let id = restoreReply { reply(id, result: NSNull()) }; restoreReply = nil
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let id = restoreReply, let url = urls.first else { return }; restoreReply = nil
        let accessed = url.startAccessingSecurityScopedResource(); defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let bytes = try Data(contentsOf: url)
            guard bytes.count < 45_000_000, let text = String(data: bytes, encoding: .utf8) else { throw NativeError.message("45 MB 以下の JSON ファイルを選んでください。") }
            reply(id, result: text)
        } catch { reply(id, error: error.localizedDescription) }
    }
    private func present(_ controller: UIViewController) {
        guard var presenter = webView?.window?.rootViewController else { return }
        while let next = presenter.presentedViewController { presenter = next }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY - 100, width: 1, height: 1)
        }
        presenter.present(controller, animated: true)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.scheme == "plainwalk-local", url.host == "app" { decisionHandler(.allow); return }
        if navigationAction.navigationType == .linkActivated, ["https", "http"].contains(url.scheme ?? "") { UIApplication.shared.open(url) }
        decisionHandler(.cancel)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, ["https", "http"].contains(url.scheme ?? "") { UIApplication.shared.open(url) }
        return nil
    }
}

final class AssetSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, url.host == "app",
              let root = Bundle.main.url(forResource: "Web", withExtension: nil) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let path = url.path == "/" || url.path.isEmpty ? "index.html" : String(url.path.dropFirst())
        let file = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(root.standardizedFileURL.resolvingSymlinksInPath().path + "/"),
              let data = try? Data(contentsOf: file) else { urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist)); return }
        let types = ["html": "text/html", "js": "text/javascript", "css": "text/css", "json": "application/json", "geojson": "application/geo+json", "webmanifest": "application/manifest+json", "png": "image/png", "svg": "image/svg+xml", "jpg": "image/jpeg", "webp": "image/webp"]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": types[file.pathExtension] ?? "application/octet-stream", "Access-Control-Allow-Origin": "*", "Cache-Control": "no-cache"])!
        urlSchemeTask.didReceive(response); urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
