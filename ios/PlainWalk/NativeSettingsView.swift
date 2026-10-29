import SwiftUI

@MainActor struct NativeSettingsView: View {
    @State private var config: [String: Any]
    @State private var notice: String?
    let onChange: ([String: Any]) -> Void
    let onAction: (String) -> Void
    let onClose: () -> Void
    init(config: [String: Any], onChange: @escaping ([String: Any]) -> Void, onAction: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        _config = State(initialValue: config); self.onChange = onChange; self.onAction = onAction; self.onClose = onClose
    }
    private let page = Color(uiColor: .systemGroupedBackground)
    private func binding(_ key: String) -> Binding<Bool> {
        Binding(get: { config[key] as? Bool ?? false }, set: { config[key] = $0; onChange(config) })
    }
    private func choice(_ key: String, fallback: String) -> Binding<String> {
        Binding(get: { config[key] as? String ?? fallback }, set: { config[key] = $0; onChange(config) })
    }
    private func row(_ title: String, icon: String? = nil, action: String) -> some View {
        Button { onAction(action) } label: {
            HStack(spacing: 14) { if let icon { Image(systemName: icon).foregroundStyle(.blue).frame(width: 23) }; Text(title).foregroundStyle(.primary); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.caption.weight(.semibold)) }.padding(.vertical, 14).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func section<Content: View>(_ title: String? = nil, description: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 16) }
            VStack(spacing: 0, content: content).padding(.horizontal, 16).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 25))
            if let description { Text(description).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16).fixedSize(horizontal: false, vertical: true) }
        }
    }
    private func unsupported(_ label: String) -> some View {
        Button { notice = "この機能の自動検知との接続はまだ完了していません。手動で「軌跡を残す」を使えます。" } label: { HStack { Text(label); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.caption) }.foregroundStyle(.primary).padding(.vertical, 14) }.buttonStyle(.plain)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Button(action: onClose) { Image(systemName: "chevron.left").font(.title2.weight(.medium)).frame(width: 44, height: 44).background(.regularMaterial, in: Circle()).shadow(color: .black.opacity(0.07), radius: 16, y: 8) }.tint(.primary).accessibilityLabel("戻る"); Spacer(); Text("設定").font(.headline); Spacer(); Color.clear.frame(width: 44, height: 44) }.padding(.horizontal, 16).padding(.vertical, 14).background(page)
            ScrollView {
                VStack(spacing: 27) {
                    section("動き出したとき", description: "手動で始めた記録と、アプリを閉じた間の移動検知は別の機能です。") {
                        HStack { Text("何もしない"); Spacer(); Image(systemName: "checkmark").foregroundStyle(.blue) }.padding(.vertical, 14)
                        Divider(); unsupported("知らせる"); Divider(); unsupported("自動で記録する")
                    }
                    section("自宅・職場・よく行く場所", description: "場所からの自動記録は未接続です。場所を有効にした表示にはしません。") { unsupported("自宅"); Divider(); unsupported("職場"); Divider(); unsupported("場所を追加") }
                    section(description: "白地図と端末の表示モードを切り替えます。") {
                        Picker("外観", selection: choice("dark", fallback: "auto")) { Text("ライト").tag("light"); Text("ダーク").tag("dark"); Text("端末に合わせる").tag("auto") }.pickerStyle(.menu).padding(.vertical, 8)
                    }
                    section { Picker("単位", selection: choice("units", fallback: "auto")) { Text("地域に合わせる (km)").tag("auto"); Text("キロメートル").tag("km"); Text("マイル").tag("mi") }.pickerStyle(.menu).padding(.vertical, 8) }
                    section("歩数") { row("1 日の歩数の目標", icon: "target", action: "steps") }
                    section("カメラ") { row("LUT", icon: "camera.filters", action: "lutSettings") }
                    section("通知", description: "許可と時刻を含む通知設定を開きます。") { row("朝・週間ふりかえりの通知", icon: "bell", action: "notificationSettings") }
                    section("Apple ヘルスケア", description: "許可したデータだけを読み込みます。Playgrounds 版では利用できません。") { row("ワークアウトを選んで描く", icon: "figure.walk", action: "healthImport") }
                    section("取り込み") { row("ファイルからさんぽを取り込む", icon: "square.and.arrow.down", action: "nativeImport") }
                    section("書き出し") { row("すべてのさんぽを GPX で書き出す", icon: "square.and.arrow.up", action: "gpxExportAll") }
                    section("バックアップ", description: "共有シートの「ファイルに保存」から自分の iCloud Drive も選べます。") { row("バックアップを書き出す", icon: "arrow.up.doc", action: "backup"); Divider(); row("バックアップを取り込む", icon: "arrow.down.doc", action: "nativeRestore") }
                    section("アプリについて") { row("バージョン 0.3.0", action: "about"); Divider(); row("対応範囲", action: "limitations") }
                    section("beta") { Toggle("beta 機能", isOn: binding("beta")).padding(.vertical, 10); if config["beta"] as? Bool == true { Divider(); Toggle("画面をスリープさせない", isOn: binding("wake")).padding(.vertical, 10); Divider(); Toggle("GPS 精度を表示", isOn: binding("accuracy")).padding(.vertical, 10) } }
                    section("開発者向け", description: "座標や写真を含めない診断情報で、権限・保存・実機の動作を確認します。") { Toggle("開発者モード", isOn: binding("developerMode")).padding(.vertical, 10); if config["developerMode"] as? Bool == true { Divider(); row("実機検証・診断ログ", icon: "stethoscope", action: "nativeDeveloper") } }
                }.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 30)
            }
            HStack { tab("マイマップ", icon: "sparkles", action: "tab:map"); tab("記録", icon: "chart.bar.fill", action: "tab:records"); tab("プロフィール", icon: "person", action: "tab:profile") }.padding(.top, 10).background(Color(uiColor: .systemBackground)).overlay(alignment: .top) { Divider() }
        }.background(page).onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-PlainWalkNativeSettingsSmokeTest") {
                let folder=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("PlainWalk",isDirectory:true)
                try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                try? Data("{\"nativeSettings\":true}".utf8).write(to:folder.appendingPathComponent("native-settings-ready.json"),options:.atomic)
            }
            #endif
        }.alert("実装状況", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) { Button("わかりました", role: .cancel) {} } message: { Text(notice ?? "") }
    }
    private func tab(_ title: String, icon: String, action: String) -> some View {
        Button { onAction(action) } label: { VStack(spacing: 4) { Image(systemName: icon).font(.system(size: 21)); Text(title).font(.system(size: 10)) }.frame(maxWidth: .infinity).foregroundStyle(action == "tab:profile" ? Color.primary : Color.secondary) }.buttonStyle(.plain).accessibilityLabel(title)
    }
}
