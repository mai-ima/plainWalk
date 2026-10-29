import SwiftUI

/// Preferences are the same persisted keys used by the Web library. Every control
/// below changes native map rendering, including bundled licensed Japan outlines.
@MainActor struct NativeLayerView: View {
    @ObservedObject var model: NativeAppModel
    @Environment(\.dismiss) private var dismiss

    private var theme: Int { Int(min(Double(NativeLayerPalette.all.count - 1), max(0, nativeNumber(model.config["theme"]) ?? 0))) }
    private var pin: String { model.config["pin"] as? String ?? "badge" }
    private var marker: String { model.config["locationMark"] as? String ?? "dot" }
    private let pinChoices = [("badge", "バッジ"), ("circle", "丸"), ("square", "正方形"), ("outline", "輪郭"), ("dot", "点")]
    private let markerChoices = [("dot", "点"), ("black", "黒猫"), ("tabby", "茶トラ"), ("calico", "三毛"), ("silver", "サバトラ")]
    private let transportChoices = [("walking", "徒歩", "figure.walk"), ("running", "ランニング", "figure.run"), ("cycling", "自転車", "bicycle"), ("vehicle", "乗り物", "car.fill")]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    choicesSection("配色", note: "選んだ配色で、白地図と軌跡を描きます。") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(NativeLayerPalette.all.enumerated()), id: \.offset) { index, item in
                                    choice(item.name, selected: theme == index) {
                                        NativePaperLineSample(dashed: false)
                                            .stroke(item.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                            .padding(11).background(item.paper, in: Circle())
                                    } action: { choose("theme", index) }
                                    .containerRelativeFrame(.horizontal, count: 5, spacing: 12)
                                }
                            }.padding(4)
                        }
                    }
                    choicesSection("線") {
                        HStack(spacing: 12) {
                            choice("実線", selected: model.config["line"] as? String != "dashed") {
                                lineSample(dashed: false)
                            } action: { choose("line", "solid") }
                            choice("点線", selected: model.config["line"] as? String == "dashed") {
                                lineSample(dashed: true)
                            } action: { choose("line", "dashed") }
                            Spacer(minLength: 0)
                        }.padding(4)
                    }
                    choicesSection("写真ピン") {
                        HStack(spacing: 0) {
                            ForEach(pinChoices, id: \.0) { item in
                                choice(item.1, selected: pin == item.0 || (pin == "card" && item.0 == "badge")) {
                                    pinSample(item.0)
                                } action: { choose("pin", item.0) }
                                .frame(maxWidth: .infinity)
                            }
                        }.padding(.vertical, 4)
                    }
                    choicesSection("現在地", note: "歩くと猫も歩きます。地図を大きく引いたときは、現在地を点で表示します。") {
                        HStack(spacing: 0) {
                            ForEach(markerChoices, id: \.0) { item in
                                choice(item.1, selected: marker == item.0) {
                                    if item.0 == "dot" { Circle().fill(model.ink).frame(width: 13, height: 13) }
                                    else { NativePaperCompanion(kind: item.0).frame(width: 28, height: 44).scaleEffect(0.8) }
                                } action: { choose("locationMark", item.0) }
                                .frame(maxWidth: .infinity)
                            }
                        }.padding(.vertical, 4)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        card { Toggle("地図の輪郭を表示", isOn: bool("outline", default: false)) }
                        note("市区町村の境と海岸線を薄い線で表示します。日本の境界データに対応しています。")
                        note("境界データ：国土数値情報（国土交通省）を加工。CC BY 4.0。Geo.maderaojen.me の簡略化データを使用。")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        card { Toggle("記録中は他の軌跡を薄くする", isOn: bool("fadeOther", default: true)) }
                        note("記録中は、ほかの軌跡を薄くして、いま歩いている形を見やすくします。")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("移動手段")
                        card {
                            VStack(spacing: 0) {
                                ForEach(Array(transportChoices.enumerated()), id: \.offset) { index, item in
                                    Toggle(isOn: transport(item.0)) {
                                        Label { Text(item.1) } icon: { Image(systemName: item.2).font(.title3).foregroundStyle(.blue).frame(width: 28) }
                                    }.padding(.vertical, 3)
                                    if index < transportChoices.count - 1 { Divider().padding(.leading, 42).padding(.vertical, 12) }
                                }
                            }
                        }
                        note("オフにすると、その手段で動いた区間を白地図に描きません。記録した距離や開拓距離は変わりません。")
                    }
                    card {
                        VStack(spacing: 0) {
                            preference("よく通る道を太く表示", key: "thicken", initial: true)
                            preference("軌跡を整える", key: "smooth", initial: true)
                            preference("方眼グリッドを表示", key: "grid", initial: false)
                            preference("現在地のハイライト", key: "highlight", initial: true)
                            preference("写真を表示", key: "showPhotos", initial: true)
                            Toggle("つぶやきを表示", isOn: bool("showTweets", default: false))
                        }
                    }
                }.padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("地図レイヤー").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() }.fontWeight(.semibold).foregroundStyle(.primary) } }
        }
        .tint(.green)
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
    }

    private func choose(_ key: String, _ value: Any) { model.haptic(); model.updateConfig(key: key, value: value) }
    private func bool(_ key: String, default initial: Bool) -> Binding<Bool> {
        Binding(get: { model.config[key] as? Bool ?? initial }, set: { choose(key, $0) })
    }
    private func transport(_ key: String) -> Binding<Bool> {
        Binding(get: { (model.config["transportVisible"] as? [String: Bool])?[key] ?? true }, set: { value in
            var choices = model.config["transportVisible"] as? [String: Bool] ?? [:]
            choices[key] = value; choose("transportVisible", choices)
        })
    }
    private func sectionTitle(_ title: String) -> some View { Text(title).font(.headline).foregroundStyle(.secondary).padding(.horizontal, 15) }
    private func note(_ text: String) -> some View { Text(text).font(.footnote).foregroundStyle(.secondary).lineSpacing(3).padding(.horizontal, 15).fixedSize(horizontal: false, vertical: true) }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().font(.body).padding(.horizontal, 16).padding(.vertical, 17).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 27))
    }
    private func choicesSection<Content: View>(_ title: String, note text: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(title)
            card(content)
            if let text { note(text) }
        }
    }
    private func choice<Sample: View>(_ name: String, selected: Bool, @ViewBuilder sample: () -> Sample, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                sample().frame(width: 43, height: 43)
                    .frame(width: 47, height: 47)
                    .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                    .overlay { Circle().stroke(selected ? model.ink : model.ink.opacity(0.13), lineWidth: selected ? 2 : 1) }
                Text(name).font(.system(size: 10)).foregroundStyle(selected ? .primary : .secondary).lineLimit(1).minimumScaleFactor(0.6)
            }.frame(minWidth: 47, minHeight: 72).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(name).accessibilityValue(selected ? "選択中" : "")
    }
    private func lineSample(dashed: Bool) -> some View {
        NativePaperLineSample(dashed: dashed).stroke(model.ink, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: dashed ? [0.1, 4] : [])).padding(7)
    }
    @ViewBuilder private func pinSample(_ style: String) -> some View {
        if style == "dot" { Circle().fill(model.ink).frame(width: 9, height: 9) }
        else {
            Image(systemName: "heart.fill").font(.system(size: 13)).foregroundStyle(model.ink)
                .frame(width: 25, height: 28)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: style == "circle" || style == "outline" ? 14 : style == "square" ? 0 : 7))
                .overlay { RoundedRectangle(cornerRadius: style == "circle" || style == "outline" ? 14 : style == "square" ? 0 : 7).stroke(model.ink.opacity(style == "outline" ? 0.9 : 0.2), lineWidth: style == "outline" ? 2 : 1) }
        }
    }
    private func preference(_ title: String, key: String, initial: Bool) -> some View {
        VStack(spacing: 0) {
            Toggle(title, isOn: bool(key, default: initial))
            Divider().padding(.vertical, 12)
        }
    }
}

struct NativeLayerPalette {
    var name: String; var paper: Color; var ink: Color
    private init(_ name: String, _ paper: UInt32, _ ink: UInt32) {
        self.name = name
        self.paper = Color(red: Double((paper >> 16) & 255) / 255, green: Double((paper >> 8) & 255) / 255, blue: Double(paper & 255) / 255)
        self.ink = Color(red: Double((ink >> 16) & 255) / 255, green: Double((ink >> 8) & 255) / 255, blue: Double(ink & 255) / 255)
    }
    static let all = [
        Self("白地図", 0xfafbf9, 0x1d211e), Self("ミント", 0xeff7f2, 0x143028), Self("さくら", 0xfcf1f3, 0x35171f),
        Self("ラベンダー", 0xf3f1fa, 0x221b3a), Self("スカイ", 0xeef4fb, 0x12253a), Self("セピア", 0xf8f2e6, 0x33270f),
        Self("フォレスト", 0xf0f4ec, 0x172913), Self("ピーチ", 0xfcf1ea, 0x3b2015), Self("レモン", 0xfbf7e3, 0x332b0d),
        Self("ティール", 0xeaf5f4, 0x0f2c2d), Self("ストーン", 0xf2f2ef, 0x1f1f1d), Self("マスタード", 0xe9be4f, 0x2a1f04),
        Self("テラコッタ", 0xe0956f, 0x33150b), Self("オリーブ", 0xbdbb74, 0x1f2008), Self("デニム", 0x93b1d8, 0x0b1b30)
    ]
}
