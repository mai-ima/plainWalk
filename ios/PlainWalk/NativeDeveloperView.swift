import SwiftUI

private struct DiagnosticExport: Identifiable { let id = UUID(); let url: URL }
@MainActor struct NativeDeveloperView: View {
    @ObservedObject var recorder: LocationRecorder
    @Environment(\.dismiss) private var dismiss
    @State private var report: [String: Any] = [:]
    @State private var result = "未実行"
    @State private var events: [[String: String]] = []
    @State private var export: DiagnosticExport?
    @State private var exportFolder: URL?
    @AppStorage("plainwalk-device-checks") private var checksJSON = "{}"
    private let checks = [("launch","起動と初回表示"),("location","位置情報の許可・拒否"),("record","記録・一時停止・再開"),("background","画面ロック中の記録"),("recovery","再起動後の復元"),("media","写真・動画と共有"),("backup","バックアップの入出力"),("offline","オフライン表示"),("accessibility","VoiceOver・文字サイズ")]
    private var checkValues: [String: Int] { (try? JSONSerialization.jsonObject(with: Data(checksJSON.utf8)) as? [String: Int]) ?? [:] }
    private func record(_ code: String, count: Int? = nil) { var item=["time": ISO8601DateFormatter().string(from: Date()),"code":code];if let count {item["count"]=String(count)}; events.append(item); if events.count > 100 { events.removeFirst(events.count - 100) } }
    private func value(_ key: String) -> String { (report[key] is NSNull) ? "未取得" : (report[key].map { String(describing: $0) } ?? "不明") }
    private func refresh() async { report = await DiagnosticService.snapshot(recorder: recorder); record("snapshotRead") }
    var body: some View {
        NavigationStack {
            Form {
                Section("実機の状態") {
                    LabeledContent("実行環境", value: value("flavor")); LabeledContent("OS", value: value("systemVersion")); LabeledContent("端末", value: value("deviceFamily"))
                    LabeledContent("記録", value: recorder.session?.recording == true ? "記録中" : "停止・一時停止")
                    LabeledContent("記録点", value: String(recorder.session?.points.count ?? 0)); LabeledContent("GPS 精度", value: value("lastAccuracy") + " m")
                    Button("状態を更新") { Task { await refresh() } }
                }
                Section("権限（確認だけでは要求しません）") {
                    LabeledContent("位置情報", value: value("locationAuthorization")); LabeledContent("位置の精度", value: value("accuracyAuthorization")); LabeledContent("モーション", value: value("motionAuthorization")); LabeledContent("カメラ", value: value("cameraAuthorization")); LabeledContent("マイク", value: value("microphoneAuthorization")); LabeledContent("通知", value: value("notificationAuthorization"))
                }
                Section("保存と復元の検証") {
                    Button("保存を往復テスト") { do { let output = try DiagnosticService.storageTest(); result = "保存と読み取りが一致 · \(output["durationMs"] ?? 0) ms"; record("storagePassed") } catch { result = "保存の往復テストに失敗しました"; record("storageFailed") } }
                    #if DEBUG
                    Button("記録の復元テスト（隔離領域）") { do { _ = try LocationRecorder.persistenceSelfTest(); result = "ジャーナル復元・重複排除を確認"; record("recoveryPassed") } catch { result = "記録の復元テストに失敗しました"; record("recoveryFailed") } }
                    Button("保存失敗と再試行テスト（隔離領域）") {
                        do { _ = try NativeAppModel.stateSelfTest(); result = "保存失敗時の保持・再試行・二重保存の防止を確認"; record("transactionPassed") }
                        catch { result = "保存失敗と再試行のテストに失敗しました"; record("transactionFailed") }
                    }
                    Button("GPX・共有ファイルの互換テスト") {
                        do { _ = try NativeTrackIO.selfTest(); _ = try NativeAppModel.importSelfTest(); result = "GPX / TCX の断絶・時刻・共有ファイルの互換を確認"; record("interchangePassed") }
                        catch { result = "ファイル互換テストに失敗しました"; record("interchangeFailed") }
                    }
                    #endif
                    Text(result).font(.footnote).foregroundStyle(.secondary)
                }
                Section { ForEach(checks, id: \.0) { key, label in
                    Button { var next=checkValues; next[key]=((next[key] ?? 0)+1)%3; if let bytes=try? JSONSerialization.data(withJSONObject: next), let text=String(data:bytes,encoding:.utf8) {checksJSON=text} } label: { HStack {Text(label).foregroundStyle(.primary); Spacer(); Text(["未確認","確認済み","不具合あり"][min(2,max(0,checkValues[key] ?? 0))]).font(.footnote).foregroundStyle(.secondary)} }
                }} header: { Text("自分で確認した実機結果") } footer: { Text("背景 GPS は Xcode 版で検証します。Playgrounds 版は前面記録用です。チェック結果は自動で合格にしません。") }
                Section("診断の書き出し") {
                    Button("診断 JSON を共有") { Task { await refresh(); do { var output=report; output["version"]=1; output["createdAt"]=ISO8601DateFormatter().string(from:Date()); output["checks"]=Dictionary(uniqueKeysWithValues:checks.map { ($0.0, min(2,max(0,checkValues[$0.0] ?? 0))) }); output["events"]=events; let folder=FileManager.default.temporaryDirectory.appendingPathComponent("diagnostic-"+UUID().uuidString,isDirectory:true); try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true); let url=folder.appendingPathComponent("plainwalk-native-diagnostics.json"); try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys]).write(to:url,options:.atomic); exportFolder=folder; export=DiagnosticExport(url:url) } catch {result="診断ファイルを書き出せませんでした"} } }
                    Button("診断ログを消去", role: .destructive) {events=[]}
                    Text("座標・軌跡・写真・メモ・場所名を含めず、自動送信しません。保存テストは実際の記録を変更しない別の領域で行います。").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("実機検証").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) {Button("閉じる") {dismiss()} } }.task {await refresh()}
        }.sheet(item:$export,onDismiss:{if let exportFolder {try? FileManager.default.removeItem(at:exportFolder)};exportFolder=nil;export=nil}) { item in DiagnosticShareSheet(url:item.url) }
        .onChange(of:recorder.session?.points.count) { _, value in if let value {record("locationUpdate",count:value)} }
        .onChange(of:recorder.session?.recording) { _, value in record(value == true ? "recording" : "pausedOrStopped") }
        .onReceive(NotificationCenter.default.publisher(for:UIApplication.didEnterBackgroundNotification)) {_ in record("background")}
        .onReceive(NotificationCenter.default.publisher(for:UIApplication.didBecomeActiveNotification)) {_ in record("foreground");Task {await refresh()} }
    }
}
private struct DiagnosticShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems:[url],applicationActivities:nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
