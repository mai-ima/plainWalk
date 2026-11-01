import SwiftUI

@MainActor struct NativeSettingsView: View {
    @State private var config: [String: Any]
    @State private var notice: String?
    @State private var notificationBusy = false
    @State private var confirmingReset = false
    let onChange: ([String: Any]) -> Void
    let onAction: (String) -> Void
    let onClose: () -> Void
    let embedded: Bool
    init(config: [String: Any], onChange: @escaping ([String: Any]) -> Void, onAction: @escaping (String) -> Void, onClose: @escaping () -> Void, embedded: Bool = false) {
        _config = State(initialValue: config); self.onChange = onChange; self.onAction = onAction; self.onClose = onClose; self.embedded = embedded
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
    private func notificationBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { config[key] as? Bool ?? false }, set: { value in
            guard !notificationBusy else { return }; notificationBusy=true
            Task { defer { notificationBusy=false }; var next=config; next[key]=value
                do { try await NotificationService.configure(next); config=next; onChange(next) }
                catch { notice=error.localizedDescription }
            }
        })
    }
    private var morningTime: Binding<Date> {
        Binding(get: { let parts=(config["morningTime"] as? String ?? "07:45").split(separator:":").compactMap {Int($0)}; return Calendar.current.date(from:DateComponents(hour:parts.first ?? 7,minute:parts.count>1 ? parts[1] : 45)) ?? Date() }, set: { value in
            guard !notificationBusy else { return }; notificationBusy=true
            let parts=Calendar.current.dateComponents([.hour,.minute],from:value); var next=config; next["morningTime"]=String(format:"%02d:%02d",parts.hour ?? 7,parts.minute ?? 45)
            Task { defer { notificationBusy=false }; do { try await NotificationService.configure(next); config=next; onChange(next) } catch { notice=error.localizedDescription } }
        })
    }
    private var notificationSection: some View {
        section("通知",description:"出かける前に、そっとひと声かけます。いつでもオフにできます。") {
            Toggle("朝の通知",isOn:notificationBinding("morningNotification")).tint(.green).padding(.vertical,10)
            Divider(); DatePicker("通知する時刻",selection:morningTime,displayedComponents:.hourAndMinute).padding(.vertical,10)
            Divider(); Toggle("週間ふりかえりの通知",isOn:notificationBinding("weeklyNotification")).tint(.green).padding(.vertical,10)
            Divider(); Toggle("さんぽが途切れたら知らせる",isOn:notificationBinding("interruptionNotification")).tint(.green).padding(.vertical,10)
        }.disabled(notificationBusy)
    }
    private var healthSection: some View {
        section("Apple ヘルスケア",description:"許可した歩数や屋外ワークアウトを読み込みます。読み取り未許可とデータなしは区別できません。Playgrounds 版では利用できません。") {
            Toggle("ヘルスケアを使う",isOn:Binding(get:{config["healthEnabled"] as? Bool ?? false},set:{value in
                if !value {config["healthEnabled"]=false;onChange(config);return}
                Task {do {try await HealthService().authorize();config["healthEnabled"]=true;onChange(config)}catch{notice=error.localizedDescription}}
            })).tint(.green).padding(.vertical,10)
            Divider(); row("ワークアウトを選んで描く",icon:"figure.walk",action:"healthImport")
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Button(action: onClose) { Image(systemName: "chevron.left").font(.title2.weight(.medium)).frame(width: 44, height: 44).background(.regularMaterial, in: Circle()).shadow(color: .black.opacity(0.07), radius: 16, y: 8) }.tint(.primary).accessibilityLabel("戻る"); Spacer(); Text("設定").font(.headline); Spacer(); Color.clear.frame(width: 44, height: 44) }.padding(.horizontal, 16).padding(.vertical, 14).background(page)
            ScrollViewReader { captureProxy in
            ScrollView {
                VStack(spacing: 27) {
                    section("動き出したとき", description: "手動で始めた記録と、アプリを閉じた間の移動検知は別の機能です。") {
                        HStack { Text("何もしない"); Spacer(); Image(systemName: "checkmark").foregroundStyle(.blue) }.padding(.vertical, 14)
                        Divider(); unsupported("知らせる"); Divider(); unsupported("自動で記録する")
                    }.id("motion")
                    section("自宅・職場・よく行く場所", description: "場所の出入りに合わせて自動で記録する機能は、現在利用できません。") { unsupported("自宅"); Divider(); unsupported("職場"); Divider(); unsupported("場所を追加") }.id("places")
                    section(description: "白地図と端末の表示モードを切り替えます。") {
                        HStack { Text("外観"); Spacer(); Picker("外観", selection: choice("dark", fallback: "auto")) { Text("ライト").tag("light"); Text("ダーク").tag("dark"); Text("端末に合わせる").tag("auto") }.pickerStyle(.menu).labelsHidden().lineLimit(1).minimumScaleFactor(0.8).tint(.secondary) }.padding(.vertical, 10)
                    }.id("appearance")
                    section { HStack { Text("単位"); Spacer(); Picker("単位", selection: choice("units", fallback: "auto")) { Text("地域に合わせる (km)").tag("auto"); Text("キロメートル").tag("km"); Text("マイル").tag("mi") }.pickerStyle(.menu).labelsHidden().lineLimit(1).minimumScaleFactor(0.8).tint(.secondary) }.padding(.vertical, 10) }.id("units")
                    section("歩数") { row("1 日の歩数の目標", icon: "target", action: "steps") }.id("steps")
                    section("カメラ") { row("LUT", icon: "camera.filters", action: "lutSettings") }.id("camera")
                    notificationSection.id("notifications")
                    healthSection.id("health")
                    section("取り込み") { row("ファイルからさんぽを取り込む", icon: "square.and.arrow.down", action: "nativeImport") }.id("import")
                    section("書き出し") { row("すべてのさんぽを GPX で書き出す", icon: "square.and.arrow.up", action: "gpxExportAll") }.id("export")
                    section("バックアップ", description: "共有シートの「ファイルに保存」から自分の iCloud Drive も選べます。") { row("バックアップを書き出す", icon: "arrow.up.doc", action: "backup"); Divider(); row("バックアップを取り込む", icon: "arrow.down.doc", action: "nativeRestore") }.id("backup")
                    section("アプリについて") { row("バージョン 0.3.0", action: "about"); Divider(); row("対応範囲", action: "limitations") }.id("about")
                    section("beta") { Toggle("beta 機能", isOn: binding("beta")).padding(.vertical, 10); if config["beta"] as? Bool == true { Divider(); Toggle("画面をスリープさせない", isOn: binding("wake")).padding(.vertical, 10); Divider(); Toggle("GPS 精度を表示", isOn: binding("accuracy")).padding(.vertical, 10) } }.id("beta")
                    section { Button("データをリセット",role:.destructive) {confirmingReset=true}.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,14) }.id("reset")
                    section("開発者向け", description: "座標や写真を含めない診断情報で、権限・保存・実機の動作を確認します。") { Toggle("開発者モード", isOn: binding("developerMode")).padding(.vertical, 10); if config["developerMode"] as? Bool == true { Divider(); row("実機検証・診断ログ", icon: "stethoscope", action: "nativeDeveloper") } }.id("developer")
                }.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 30)
            }.task { await captureInitialScroll(captureProxy) }
            }
            if !embedded { HStack { tab("マイマップ", icon: "sparkles", action: "tab:map"); tab("記録", icon: "chart.bar.fill", action: "tab:records"); tab("プロフィール", icon: "person", action: "tab:profile") }.padding(.top, 10).background(Color(uiColor: .systemBackground)).overlay(alignment: .top) { Divider() } }
        }.background(page).onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-PlainWalkNativeSettingsSmokeTest") {
                let folder=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("PlainWalk",isDirectory:true)
                try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                try? Data("{\"nativeSettings\":true}".utf8).write(to:folder.appendingPathComponent("native-settings-ready.json"),options:.atomic)
            }
            #endif
        }.confirmationDialog("この端末の記録をリセットしますか？", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("すべての記録を削除", role: .destructive) { onAction("resetDataConfirmed") }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("さんぽ・写真・ノート・旗・らくがき・共有の白地図を削除します。この操作は取り消せません。必要な記録は先にバックアップを書き出してください。外観などの設定は残ります。")
        }.alert("お知らせ", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) { Button("わかりました", role: .cancel) {} } message: { Text(notice ?? "") }
    }
    private func captureInitialScroll(_ proxy:ScrollViewProxy) async {
        #if DEBUG
        let args=ProcessInfo.processInfo.arguments
        guard args.contains("-PlainWalkScreenshotFixture") else {return}
        if let key=args.first(where:{$0.hasPrefix("-PlainWalkCaptureScroll=")})?.split(separator:"=",maxSplits:1).last.map(String.init),
           ["motion","places","appearance","units","steps","camera","notifications","health","import","export","backup","about","beta","reset","developer"].contains(key) {
            await Task.yield()
            var transaction=Transaction();transaction.disablesAnimations=true
            withTransaction(transaction) {proxy.scrollTo(key,anchor:.top)}
            do {try await Task.sleep(nanoseconds:200_000_000)} catch {return}
            guard !Task.isCancelled else {return}
            captureMarker("capture-scroll.ready",value:key)
        }
        if args.contains("-PlainWalkCaptureDialog=reset") {
            confirmingReset=true
            do {try await Task.sleep(nanoseconds:200_000_000)} catch {return}
            guard !Task.isCancelled else {return}
            // This records the requested state only. The capture runner must
            // verify the visible confirmation title before accepting its image.
            captureMarker("capture-dialog.ready",value:"reset")
        }
        #endif
    }
    #if DEBUG
    private func captureMarker(_ name:String,value:String) {
        let folder=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("PlainWalk",isDirectory:true)
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        try? Data(value.utf8).write(to:folder.appendingPathComponent(name),options:.atomic)
    }
    #endif
    private func tab(_ title: String, icon: String, action: String) -> some View {
        Button { onAction(action) } label: { VStack(spacing: 4) { Image(systemName: icon).font(.system(size: 21)); Text(title).font(.system(size: 10)) }.frame(maxWidth: .infinity).foregroundStyle(action == "tab:profile" ? Color.primary : Color.secondary) }.buttonStyle(.plain).accessibilityLabel(title)
    }
}
