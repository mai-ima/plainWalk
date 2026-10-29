import SwiftUI
import MapKit
import AVKit
import UniformTypeIdentifiers

private struct NCItem: Identifiable { let id: String; let value: [String: Any] }
private func ncItems(_ value: Any?) -> [NCItem] {
    (value as? [[String: Any]] ?? []).compactMap { item in
        guard let id = item["id"] as? String else { return nil }
        return NCItem(id: id, value: item)
    }
}
private func ncData(_ value: Any?, prefix: String = "data:image/") -> Data? {
    guard let text = value as? String, text.hasPrefix(prefix), let range = text.range(of: ";base64,"), text.utf8.count <= 22_000_000 else { return nil }
    return Data(base64Encoded: String(text[range.upperBound...]))
}
private func ncDay(_ date: Date = Date()) -> String {
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
}
private func ncText(_ text: String, utf16Limit: Int) -> String {
    var result = "", count = 0
    for character in text { let size = String(character).utf16.count; if count + size > utf16Limit { break }; result.append(character); count += size }; return result
}
private func ncDate(_ ms: Double) -> String { Date(timeIntervalSince1970: ms / 1000).formatted(date: .abbreviated, time: .shortened) }

@MainActor struct NativeCollectionsView: View {
    @ObservedObject var model: NativeAppModel
    let collection: NativeCollection
    var standalone = false
    @Environment(\.dismiss) private var dismiss
    @State private var creatingPaper = false
    @State private var drawing = false
    @State private var editingDay: String?
    @State private var sharingSticker = false
    private var title: String {
        switch collection { case .spots: return "ここいいな"; case .stickers: return "ステッカー"; case .badges: return "エリアバッジ"; case .doodles: return "らくがき"; case .sharedMaps: return "共有の白地図"; case .bookmarks: return "気になる場所"; case .notes: return "ノート" }
    }
    var body: some View {
        Group {
            if standalone { NavigationStack { page } } else { page }
        }.sheet(isPresented: $creatingPaper) { NCPaperEditor(model: model) }
            .sheet(isPresented: $drawing) { NCDoodleEditor(model: model) }
            .sheet(isPresented: Binding(get: { editingDay != nil }, set: { if !$0 { editingDay = nil } })) { if let day = editingDay { NCNoteEditor(model: model, day: day) } }
            .sheet(isPresented: $sharingSticker) { NCStickerPicker(model: model) }
    }
    private var page: some View {
            content.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden()
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "chevron.left").font(.title3.weight(.medium)).frame(width: 44, height: 44) }.accessibilityLabel("戻る") }
                    if collection == .spots && model.isRecording { ToolbarItem(placement: .topBarTrailing) { Button { model.openSpotCapture() } label: { Image(systemName: "camera") }.accessibilityLabel("ここいいなを残す") } }
                    if collection == .notes { ToolbarItem(placement: .topBarTrailing) { Button { editingDay = ncDay() } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel("今日のノートを書く") } }
                    if collection == .doodles { ToolbarItem(placement: .topBarTrailing) { Button { drawing = true } label: { Image(systemName: "pencil.tip") }.accessibilityLabel("らくがきを描く") } }
                }
    }
    @ViewBuilder private var content: some View {
        switch collection {
        case .spots: spots
        case .stickers: stickers
        case .badges: NCBadgesView(model: model)
        case .doodles: doodles
        case .sharedMaps: papers
        case .bookmarks: bookmarks
        case .notes: notes
        }
    }
    private func message(_ heading: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 9) { Text(heading).font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary).lineSpacing(4) }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 25))
    }
    private var spots: some View {
        Group {
            if model.spots.isEmpty {
                NCEmptyView(symbol: "camera", title: "まだ「ここいいな」がありません", detail: "さんぽ中に「ここいいな」を残すと、ここに並びます。")
            } else {
                ScrollView { LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(model.spots.reversed()) { spot in
                        NavigationLink { NCSpotDetail(model: model, spotID: spot.id) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Group { if let data = spot.photoData, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() } else { ZStack { Color(uiColor: .secondarySystemBackground); Image(systemName: video(for: spot.id) ? "video" : "heart").font(.largeTitle).foregroundStyle(.secondary) } } }.frame(height: 165).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 18))
                                Text(spot.text.isEmpty ? "ここいいな" : spot.text).font(.subheadline.weight(.medium)).lineLimit(2)
                                Text(ncDate(spot.point.t)).font(.caption2).foregroundStyle(.secondary)
                            }.foregroundStyle(.primary)
                        }.buttonStyle(.plain)
                    }
                }.padding(16) }
            }
        }.background(Color(uiColor: .systemBackground))
    }
    private func video(for id: String) -> Bool { ncItems(model.library["spots"]).first(where: { $0.id == id })?.value["video"] is String }
    private var stickers: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Button { sharingSticker = true } label: {
                    HStack(spacing: 12) { Image(systemName: "arrow.left.arrow.right").font(.title3).foregroundStyle(.white).frame(width: 40, height: 40).background(.black, in: Circle()); VStack(alignment: .leading, spacing: 4) { Text("近くの人と交換・あげる").font(.subheadline.weight(.semibold)).foregroundStyle(.primary); Text("1 枚ずつ選んで、AirDrop などで渡せます。").font(.footnote).foregroundStyle(.secondary) }; Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }.padding(15).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain)
                if ncStickers(model.library).isEmpty { Text("ここいいなの写真から切り抜いたステッカーが、ここに集まります。").foregroundStyle(.secondary).font(.subheadline).lineSpacing(5).padding(.horizontal, 16) }
                else { NCStickerGrid(model: model) }
            }.padding(16)
        }
    }
    private var doodles: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("答え合わせマップに絵を描いて、いつか歩いてみる。").font(.headline)
                    Text("実際の地図を 1 本指でなぞって描いた絵を、歩くまで取っておきます。移動したいときは「地図を動かす」に切り替えます。").font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
                    Button { drawing = true } label: { Label("らくがきを描く", systemImage: "pencil.tip").font(.subheadline.weight(.semibold)).padding(.horizontal, 16).padding(.vertical, 10).foregroundStyle(Color(uiColor: .systemBackground)).background(Color.primary, in: Capsule()) }.buttonStyle(.plain)
                }.padding(18).background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 22))
                    .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(Color.primary.opacity(0.08),lineWidth:1) }
                ForEach(ncItems(model.library["doodles"])) { item in NavigationLink { NCDoodleDetail(model: model, itemID: item.id) } label: {
                    HStack { NCLineThumbnail(points: (item.value["points"] as? [[String: Any]] ?? []).compactMap(NativePoint.init(json:))).frame(width: 85, height: 75); VStack(alignment: .leading) { Text(item.value["name"] as? String ?? "らくがき").font(.headline); if let time = item.value["created"] as? Double { Text(ncDate(time)).font(.caption).foregroundStyle(.secondary) } }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }.padding(12).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain) }
            }.padding(16)
        }
    }
    private var bookmarks: some View {
        ScrollView { VStack(spacing: 20) {
            let items = ncItems(model.library["bookmarks"])
            if items.isEmpty { message("気になる場所はまだありません", "答え合わせマップで場所を探して、しおりを押すとここに入ります。行ってみたくなったら「ここへ向かう」。白地図に旗が立って方角を示します。") }
            else { VStack(spacing: 0) { ForEach(items) { item in
                if let point = NativePoint(json: item.value) {
                    NavigationLink { NCBookmarkDetail(model: model, itemID: item.id) } label: { HStack { Image(systemName: "bookmark"); Text(item.value["name"] as? String ?? "気になる場所"); Spacer(); if let current = model.currentPoint { Text(model.distanceText(ncDistance(current, point)) + " " + model.distanceUnit).font(.caption).foregroundStyle(.secondary) }; Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }.padding(16).foregroundStyle(.primary) }
                    if item.id != items.last?.id { Divider().padding(.leading, 16) }
                }
            }}.background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24)) }
            Button { dismiss(); model.openAnswerMap() } label: { Label("答え合わせマップで探す", systemImage: "map").frame(maxWidth: .infinity).padding(14) }.background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
        }.padding(16).padding(.top, 12) }.background(Color(uiColor: .systemGroupedBackground))
    }
    private var papers: some View {
        ScrollView { VStack(spacing: 24) {
            let items = ncItems(model.library["sharedMaps"])
            if items.isEmpty { message("共有の白地図はまだありません", "紙を作って、送りたいさんぽの線だけをまとめられます。") }
            else { ForEach(items) { item in NavigationLink { NCPaperDetail(model: model, itemID: item.id) } label: {
                HStack { Image(systemName: "map").font(.title2); VStack(alignment: .leading, spacing: 4) { Text(item.value["name"] as? String ?? "みんなのさんぽ").font(.headline); Text("\((item.value["walks"] as? [[String: Any]] ?? []).count) 本の道").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }.padding(18).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
            }.buttonStyle(.plain) } }
            Button { creatingPaper = true } label: { Label("紙を作る", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading).padding(17) }.background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            Text("選んださんぽの線だけを白地図ファイルにして渡します。写真・メモ・日時は含めません。招待リンクによる共同編集・自動同期には対応していません。").font(.footnote).foregroundStyle(.secondary).lineSpacing(4).padding(.horizontal, 16)
        }.padding(16).padding(.top, 12) }.background(Color(uiColor: .systemGroupedBackground))
    }
    private var notes: some View {
        let values = model.library["notes"] as? [String: [String: Any]] ?? [:]
        return ScrollView { LazyVStack(spacing: 16) {
            if values.isEmpty { message("まだノートがありません", "今日のさんぽを、写真や道と一緒に紙の上に残します。右上のボタンから今日のノートを書けます。") }
            ForEach(values.keys.sorted().reversed(), id: \.self) { day in
                Button { editingDay = day } label: { VStack(alignment: .leading, spacing: 8) { Text(day).font(.headline); Text(values[day]?["text"] as? String ?? "今日のノート").font(.subheadline).foregroundStyle(.secondary).lineLimit(3); if let layout = values[day]?["layout"] as? [[String: Any]], !layout.isEmpty { Label("\(layout.count) 枚の貼りもの", systemImage: "photo.on.rectangle").font(.caption).foregroundStyle(.secondary) } }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20)) }.buttonStyle(.plain)
            }
        }.padding(16) }
    }
}

private struct NCEmptyView: View {
    let symbol: String; let title: String; let detail: String
    var body: some View { VStack(spacing: 15) { Image(systemName: symbol).font(.system(size: 51, weight: .regular)).foregroundStyle(.secondary); Text(title).font(.title3.weight(.semibold)).multilineTextAlignment(.center); Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(uiColor: .systemBackground)) }
}
private struct NCLineThumbnail: View {
    let points: [NativePoint]
    var body: some View { Canvas { context, size in
        guard !points.isEmpty else { return }
        let lat = points.map(\.lat), lon = points.map(\.lon), minLat = lat.min()!, maxLat = lat.max()!, minLon = lon.min()!, maxLon = lon.max()!, cosine = cos((minLat + maxLat) * .pi / 360)
        let scale = max(max((maxLon - minLon) * cosine / max(1, size.width - 18), (maxLat - minLat) / max(1, size.height - 18)), 0.0000001)
        var path = Path(); for (index, point) in points.enumerated() { let p = CGPoint(x: ((point.lon - (minLon + maxLon) / 2) * cosine / scale) + size.width / 2, y: size.height / 2 - (point.lat - (minLat + maxLat) / 2) / scale); if index == 0 || point.isBreak { path.move(to: p) } else { path.addLine(to: p) } }; context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
    }.accessibilityHidden(true) }
}

@MainActor private struct NCSpotDetail: View {
    @ObservedObject var model: NativeAppModel; let spotID: String
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?; @State private var videoFolder: URL?; @State private var deleting = false; @State private var cutting = false
    private var raw: [String: Any]? { ncItems(model.library["spots"]).first(where: { $0.id == spotID })?.value }
    var body: some View {
        ScrollView { VStack(spacing: 20) {
            if let spot = model.spots.first(where: { $0.id == spotID }) {
                if let player { VideoPlayer(player: player).frame(height: 400).clipShape(RoundedRectangle(cornerRadius: 23)) }
                else if let data = spot.photoData, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 23)) }
                else { Image(systemName: "heart").font(.system(size: 70)).foregroundStyle(.secondary).padding(40) }
                Text(spot.text.isEmpty ? "ここいいな" : spot.text).font(.title3.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                Text(ncDate(spot.point.t)).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                if let data = spot.photoData {
                    Button { model.shareData(data, name: "plainwalk-photo.jpg") } label: { Label("写真を共有", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(13) }.buttonStyle(.bordered)
                    Button { Task { await makeSticker(data) } } label: { Label(cutting ? "切り抜いています…" : "写真からステッカーを作る", systemImage: "wand.and.stars").frame(maxWidth: .infinity).padding(13) }.buttonStyle(.bordered).disabled(cutting)
                }
                if let data = ncData(raw?["video"], prefix: "data:video/") { Button { model.shareData(data, name: (raw?["videoType"] as? String ?? "").contains("quicktime") ? "plainwalk-video.mov" : "plainwalk-video.mp4") } label: { Label("動画を共有", systemImage: "square.and.arrow.up") } }
                Button(role: .destructive) { deleting = true } label: { Label("この「ここいいな」を削除", systemImage: "trash") }
            } else { NCEmptyView(symbol: "camera", title: "見つかりませんでした", detail: "この「ここいいな」は削除された可能性があります。") }
        }.padding(20) }.navigationTitle("ここいいな").navigationBarTitleDisplayMode(.inline).task { prepareVideo() }.onDisappear { player?.pause(); if let videoFolder { try? FileManager.default.removeItem(at: videoFolder) } }.confirmationDialog("この「ここいいな」を削除しますか？", isPresented: $deleting, titleVisibility: .visible) { Button("削除", role: .destructive) { do { try model.updateLibrary { library in library["spots"] = (library["spots"] as? [[String: Any]] ?? []).filter { $0["id"] as? String != spotID } }; dismiss() } catch { model.showError(error.localizedDescription) } } }
    }
    private func prepareVideo() {
        guard player == nil, let raw, let bytes = ncData(raw["video"], prefix: "data:video/") else { return }
        do { let folder = FileManager.default.temporaryDirectory.appendingPathComponent("plainwalk-video-" + UUID().uuidString, isDirectory: true); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); let url = folder.appendingPathComponent((raw["videoType"] as? String ?? "").contains("quicktime") ? "clip.mov" : "clip.mp4"); try bytes.write(to: url, options: .atomic); videoFolder = folder; player = AVPlayer(url: url) } catch { model.showError("動画を読み取れませんでした。") }
    }
    private func makeSticker(_ data: Data) async {
        cutting = true; defer { cutting = false }
        do { let day = ncDay(); let existing = (model.library["notes"] as? [String: [String: Any]])?[day]?["layout"] as? [[String: Any]] ?? []; guard existing.count < 20 else { model.showError("今日のノートには 20 枚まで貼れます。"); return }; let png = try await CutoutService.cutout(data); guard png.count <= 3_500_000 else { model.showError("切り抜いた画像が大きすぎます。小さい写真でお試しください。"); return }; let image = UIImage(data: png); let ratio = (image?.size.width ?? 1) / max(1, image?.size.height ?? 1)
            guard (((model.library["notes"] as? [String: [String: Any]])?[day]?["layout"] as? [[String: Any]])?.count ?? 0) < 20 else { model.showError("今日のノートには 20 枚まで貼れます。"); return }
            try model.updateLibrary { library in
                var notes = library["notes"] as? [String: [String: Any]] ?? [:]; var note = notes[day] ?? ["day": day, "text": "", "paper": "plain", "font": "serif"]; var layout = note["layout"] as? [[String: Any]] ?? []
                guard layout.count < 20 else { return }
                layout.append(["id": UUID().uuidString, "type": "sticker", "src": "data:image/png;base64," + png.base64EncodedString(), "x": 360.0, "y": 500.0, "width": 240.0, "ratio": ratio, "rotation": -5.0, "finish": "plain"]); note["layout"] = layout; notes[day] = note; library["notes"] = notes
            }
            model.shareData(png, name: "plainwalk-sticker.png")
        } catch { model.showError(error.localizedDescription) }
    }
}

private struct NCSticker: Identifiable { let id: String; let day: String; let item: [String: Any]; var data: Data? { ncData(item["src"]) } }
private func ncStickers(_ library: [String: Any]) -> [NCSticker] {
    let notes = library["notes"] as? [String: [String: Any]] ?? [:]
    return notes.keys.sorted().reversed().flatMap { day in (notes[day]?["layout"] as? [[String: Any]] ?? []).compactMap { item in guard item["type"] as? String == "sticker", let id = item["id"] as? String else { return nil }; return NCSticker(id: id, day: day, item: item) } }
}
@MainActor private struct NCStickerGrid: View {
    @ObservedObject var model: NativeAppModel
    var body: some View { LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 20) { ForEach(ncStickers(model.library)) { sticker in if let data = sticker.data, let image = UIImage(data: data) { Button { model.shareData(data, name: "plainwalk-sticker-\(sticker.day).png") } label: { VStack(spacing: 7) { Image(uiImage: image).resizable().scaledToFit().frame(height: 105).shadow(color: .black.opacity(0.12), radius: 4, y: 3); Text(sticker.day).font(.caption2).foregroundStyle(.secondary) } }.buttonStyle(.plain).accessibilityLabel("\(sticker.day)のステッカーを共有") } } } }
}

@MainActor private struct NCEditorError: ViewModifier {
    @ObservedObject var model: NativeAppModel
    @Binding var failure: String?
    func body(content: Content) -> some View {
        content.onChange(of: model.errorMessage) { _, message in
            guard let message else { return }; failure = message; model.errorMessage = nil
        }.alert("お知らせ", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("閉じる", role: .cancel) { failure = nil }
        } message: { Text(failure ?? "") }
    }
}

@MainActor private struct NCStickerPicker: View {
    @State private var failure: String?
    @ObservedObject var model: NativeAppModel; @Environment(\.dismiss) private var dismiss
    var body: some View { NavigationStack { ScrollView { VStack(spacing: 22) { Text("渡したいステッカーを選ぶと、AirDrop などの共有先を開きます。専用の近接交換には対応していません。").font(.subheadline).foregroundStyle(.secondary); if ncStickers(model.library).isEmpty { NCEmptyView(symbol: "sparkles.rectangle.stack", title: "まだステッカーがありません", detail: "「ここいいな」の写真から被写体を切り抜いて作れます。") } else { NCStickerGrid(model: model) } }.padding(20) }.navigationTitle("ステッカーをあげる").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } } } }.modifier(NCEditorError(model: model, failure: $failure)) }

}

@MainActor private struct NCBookmarkDetail: View {
    @ObservedObject var model: NativeAppModel; let itemID: String; @Environment(\.dismiss) private var dismiss
    private var item: NCItem? { ncItems(model.library["bookmarks"]).first(where: { $0.id == itemID }) }
    var body: some View { VStack(spacing: 22) { if let item, let point = NativePoint(json: item.value) { Image(systemName: "bookmark").font(.system(size: 60)).foregroundStyle(.secondary); Text(item.value["name"] as? String ?? "気になる場所").font(.title2.weight(.semibold)); if let current = model.currentPoint { Text("現在地から \(model.distanceText(ncDistance(current, point))) \(model.distanceUnit)").foregroundStyle(.secondary) }; Button("ここへ向かう") { do { let flag = NativeFlag(id: UUID().uuidString, name: item.value["name"] as? String ?? "気になる場所", point: point); try model.updateLibrary { library in var flags = library["flags"] as? [[String: Any]] ?? []; flags.insert(flag.json, at: 0); library["flags"] = flags }; model.navigateToFlag(flag) } catch { model.showError(error.localizedDescription) } }.buttonStyle(.borderedProminent).tint(.primary); Button("しおりを外す", role: .destructive) { do { try model.updateLibrary { library in library["bookmarks"] = (library["bookmarks"] as? [[String: Any]] ?? []).filter { $0["id"] as? String != itemID } }; dismiss() } catch { model.showError(error.localizedDescription) } } } }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).navigationTitle("気になる場所").navigationBarTitleDisplayMode(.inline) }
}

@MainActor private struct NCPaperEditor: View {
    @State private var failure: String?
    @ObservedObject var model: NativeAppModel; @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var selected = Set<String>()
    var body: some View { NavigationStack { Form { Section("紙の名前") { TextField("みんなのさんぽ", text: $name) }; Section { ForEach(model.walks) { walk in Toggle(isOn: Binding(get: { selected.contains(walk.id) }, set: { if $0 { selected.insert(walk.id) } else { selected.remove(walk.id) } })) { VStack(alignment: .leading) { Text(walk.name); Text(ncDate(walk.start)).font(.caption).foregroundStyle(.secondary) } } } } header: { Text("載せるさんぽ") } footer: { Text("日時・写真・メモを取り除き、選んだ道の線だけを入れます。") } }.navigationTitle("紙を作る").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }; ToolbarItem(placement: .topBarTrailing) { Button("作る") { save() } } } }.modifier(NCEditorError(model: model, failure: $failure)) }
    private func save() {
        let chosen = model.walks.filter { selected.contains($0.id) }.map { walk -> [String: Any] in ["id": walk.id, "points": walk.points.map { p -> [String: Any] in var raw: [String: Any] = ["lat": p.lat, "lon": p.lon]; if p.isBreak { raw["break"] = true }; return raw }] }
        do { try model.updateLibrary { library in var papers = library["sharedMaps"] as? [[String: Any]] ?? []; papers.append(["id": UUID().uuidString, "name": name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "みんなのさんぽ" : ncText(name, utf16Limit: 60), "walks": chosen]); library["sharedMaps"] = papers }; dismiss() } catch { failure = error.localizedDescription }
    }
}
@MainActor private struct NCPaperDetail: View {
    @ObservedObject var model: NativeAppModel; let itemID: String; @Environment(\.dismiss) private var dismiss; @State private var deleting = false
    private var item: NCItem? { ncItems(model.library["sharedMaps"]).first(where: { $0.id == itemID }) }
    var body: some View { ScrollView { VStack(spacing: 22) { if let item { let walks = item.value["walks"] as? [[String: Any]] ?? []; NCLineThumbnail(points: walks.flatMap { row in (row["points"] as? [[String: Any]] ?? []).enumerated().compactMap { i, raw in var p = raw; if i == 0 { p["break"] = true }; return NativePoint(json: p) } }).frame(height: 290); Text("\(walks.count) 本の道").foregroundStyle(.secondary); Button { do { let cleanWalks = (item.value["walks"] as? [[String: Any]] ?? []).map { walk -> [String: Any] in ["id": walk["id"] as? String ?? UUID().uuidString, "points": (walk["points"] as? [[String: Any]] ?? []).compactMap { raw -> [String: Any]? in guard let point = NativePoint(json: raw) else { return nil }; var clean: [String: Any] = ["lat": point.lat, "lon": point.lon]; if point.isBreak { clean["break"] = true }; return clean }] }; let export: [String: Any] = ["id": item.id, "name": item.value["name"] as? String ?? "みんなのさんぽ", "walks": cleanWalks, "type": "plainwalk-white-map", "version": 1]; let data = try JSONSerialization.data(withJSONObject: export, options: [.sortedKeys]); model.shareData(data, name: "plainwalk-white-map.json") } catch { model.showError(error.localizedDescription) } } label: { Label("白地図ファイルを渡す", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(12) }.buttonStyle(.borderedProminent).tint(.primary); Text("招待リンクでの共同編集や自動同期には対応していません。").font(.footnote).foregroundStyle(.secondary); Button("この紙を削除", role: .destructive) { deleting = true } } }.padding(20) }.navigationTitle(item?.value["name"] as? String ?? "共有の白地図").navigationBarTitleDisplayMode(.inline).confirmationDialog("この紙を削除しますか？", isPresented: $deleting, titleVisibility: .visible) { Button("削除", role: .destructive) { do { try model.updateLibrary { library in library["sharedMaps"] = (library["sharedMaps"] as? [[String: Any]] ?? []).filter { $0["id"] as? String != itemID } }; dismiss() } catch { model.showError(error.localizedDescription) } } } }
}

@MainActor private struct NCNoteEditor: View {
    @State private var failure: String?
    @ObservedObject var model: NativeAppModel
    let day: String
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var loaded = false
    @State private var paper = "plain"
    @State private var font = "serif"
    @State private var layout: [[String: Any]] = []
    @State private var stickers = ""
    @State private var selectedID: String?
    private var note: [String: Any] { (model.library["notes"] as? [String: [String: Any]])?[day] ?? [:] }
    private var preview: some View { NCNotebookPreview(day: day, text: text, paper: paper, font: font, layout: layout, stickers: stickers) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(day).font(.subheadline).foregroundStyle(.secondary)
                    TextEditor(text: $text).onChange(of: text) { _, value in if value.utf16.count > 5000 { text = ncText(value, utf16Limit: 5000) } }.frame(minHeight: 150).padding(10).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 15))
                    Picker("紙", selection: $paper) { Text("白い紙").tag("plain"); Text("方眼").tag("grid"); Text("罫線").tag("lined"); Text("クラフト").tag("kraft") }
                    Picker("書体", selection: $font) { Text("セリフ").tag("serif"); Text("シンプル").tag("sans"); Text("等幅").tag("mono") }
                    preview.aspectRatio(0.75, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 6))
                    insertMenu
                    itemControls
                    Button { share() } label: { Label("画像にして共有", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(12) }.buttonStyle(.bordered)
                }.padding(20)
            }.navigationTitle("ノート").navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("保存") { save() } }
            }.onAppear {
                guard !loaded else { return }
                text = note["text"] as? String ?? ""; paper = note["paper"] as? String ?? "plain"; font = note["font"] as? String ?? "serif"; layout = note["layout"] as? [[String: Any]] ?? []; stickers = note["stickers"] as? String ?? ""; loaded = true
            }
        }.modifier(NCEditorError(model: model, failure: $failure))
    }
    private var insertMenu: some View {
        Menu {
            Menu("ここいいなの写真") {
                ForEach(model.spots.filter { $0.photoData != nil }) { spot in Button(spot.text.isEmpty ? ncDate(spot.point.t) : spot.text) { if let bytes = spot.photoData { appendImage(bytes, type: "photo", mime: "image/jpeg") } } }
                if !model.spots.contains(where: { $0.photoData != nil }) { Text("写真がありません") }
            }
            Menu("さんぽの道") { ForEach(model.walks) { walk in Button(walk.name) { appendRoute(walk) } }; if model.walks.isEmpty { Text("さんぽの記録がありません") } }
            Menu("絵文字") { ForEach(["🌿", "☕", "🌸", "✨", "🐾", "♡"], id: \.self) { emoji in Button(emoji) { append(["type": "emoji", "text": emoji, "ratio": 1.0, "width": 100.0]) } } }
        } label: { Label("写真・道・絵文字を貼る", systemImage: "plus.circle").frame(maxWidth: .infinity).padding(12) }.buttonStyle(.bordered).disabled(layout.count >= 20)
    }
    @ViewBuilder private var itemControls: some View {
        if !layout.isEmpty {
            Text("貼りものを選んで整える").font(.subheadline.weight(.semibold))
            ScrollView(.horizontal) { HStack { ForEach(Array(layout.enumerated()), id: \.offset) { index, item in Button("\(index + 1) · \(itemName(item))") { selectedID = item["id"] as? String }.buttonStyle(.bordered).tint(selectedID == item["id"] as? String ? .primary : .secondary) } } }
            if let selectedID, layout.contains(where: { $0["id"] as? String == selectedID }) {
                VStack(spacing: 12) {
                    slider("横の位置", key: "x", range: 0...720)
                    slider("縦の位置", key: "y", range: 0...960)
                    slider("大きさ", key: "width", range: 30...600)
                    slider("傾き", key: "rotation", range: -180...180)
                    Button("貼りものを外す", role: .destructive) { layout.removeAll { $0["id"] as? String == selectedID }; self.selectedID = nil }
                }.padding(14).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
    private func itemName(_ value: [String: Any]) -> String { switch value["type"] as? String { case "photo": return "写真"; case "route": return "道"; case "sticker": return "ステッカー"; default: return "絵文字" } }
    private func slider(_ title: String, key: String, range: ClosedRange<Double>) -> some View {
        HStack { Text(title).font(.caption).frame(width: 65, alignment: .leading); Slider(value: Binding(get: { layout.first(where: { $0["id"] as? String == selectedID })?[key] as? Double ?? range.lowerBound }, set: { value in if let index = layout.firstIndex(where: { $0["id"] as? String == selectedID }) { layout[index][key] = value } }), in: range) }
    }
    private func append(_ raw: [String: Any]) {
        guard layout.count < 20 else { failure = "1 ページには 20 点まで貼れます。"; return }
        let id = UUID().uuidString; var item = raw; item["id"] = id; item["x"] = 360.0; item["y"] = 500.0; item["rotation"] = -5.0; item["finish"] = "plain"; layout.append(item); selectedID = id
    }
    private func appendImage(_ bytes: Data, type: String, mime: String) {
        guard let image = UIImage(data: bytes), bytes.count <= 3_500_000 else { failure = "この画像はノートに貼れません。小さな画像を選んでください。"; return }
        let ratio = image.size.width / max(1, image.size.height)
        guard (0.01...100).contains(ratio) else { failure = "この画像の縦横比はノートに対応していません。"; return }
        let actualMime = bytes.starts(with: [137, 80, 78, 71]) ? "image/png" : bytes.starts(with: [255, 216, 255]) ? "image/jpeg" : mime
        append(["type": type, "src": "data:\(actualMime);base64," + bytes.base64EncodedString(), "width": 240.0, "ratio": ratio])
    }
    private func appendRoute(_ walk: NativeWalk) {
        let renderer = ImageRenderer(content: NCLineThumbnail(points: walk.points).padding(20).frame(width: 500, height: 400).background(Color.white)); renderer.scale = 2
        guard let bytes = renderer.uiImage?.pngData() else { failure = "さんぽの道を画像にできませんでした。"; return }; appendImage(bytes, type: "route", mime: "image/png")
    }
    private func share() {
        let renderer = ImageRenderer(content: preview.frame(width: 720, height: 960)); renderer.scale = 2
        guard let data = renderer.uiImage?.pngData() else { failure = "ノートを画像にできませんでした。"; return }
        do { try storeDraft(); model.shareData(data, name: "plainwalk-note-\(day).png") } catch { failure = error.localizedDescription }
    }
    private func storeDraft() throws {
        try model.updateLibrary { library in var notes = library["notes"] as? [String: [String: Any]] ?? [:]; var value = notes[day] ?? [:]; value["day"] = day; value["text"] = ncText(text, utf16Limit: 5000); value["paper"] = paper; value["font"] = font; value["layout"] = layout; value["stickers"] = stickers; notes[day] = value; library["notes"] = notes }
    }
    private func save() { do { try storeDraft(); dismiss() } catch { failure = error.localizedDescription } }
}
private struct NCNotebookPreview: View {
    let day: String; let text: String; let paper: String; let font: String; let layout: [[String: Any]]; let stickers: String
    var body: some View { GeometryReader { geometry in let scale = geometry.size.width / 720
        ZStack(alignment: .topLeading) {
            (paper == "kraft" ? Color(red: 0.91, green: 0.84, blue: 0.72) : Color(red: 0.985, green: 0.98, blue: 0.96))
            Canvas { context, size in if paper == "grid" || paper == "lined" { var path = Path(); for y in stride(from: CGFloat(90), to: CGFloat(960), by: 32) { path.move(to: CGPoint(x: 0, y: y * scale)); path.addLine(to: CGPoint(x: size.width, y: y * scale)) }; if paper == "grid" { for x in stride(from: CGFloat(8), to: CGFloat(720), by: 32) { path.move(to: CGPoint(x: x * scale, y: 0)); path.addLine(to: CGPoint(x: x * scale, y: size.height)) } }; context.stroke(path, with: .color(.gray.opacity(0.2)), lineWidth: 0.5) } }
            Text("PLAINWALK   " + day).font(.system(size: 16 * scale)).foregroundStyle(.secondary).position(x: 190 * scale, y: 45 * scale)
            Text(text).font(.system(size: 24 * scale, design: font == "serif" ? .serif : font == "mono" ? .monospaced : .default)).foregroundStyle(Color(red: 0.16, green: 0.19, blue: 0.15)).frame(width: 640 * scale, alignment: .topLeading).padding(.leading, 40 * scale).padding(.top, 85 * scale)
            ForEach(Array(layout.enumerated()), id: \.offset) { _, item in
                let width = min(600, max(30, item["width"] as? Double ?? 150)), ratio = max(0.01, item["ratio"] as? Double ?? 1), x = item["x"] as? Double ?? 0, y = item["y"] as? Double ?? 0
                Group { if item["type"] as? String == "emoji" { Text(item["text"] as? String ?? "✦").font(.system(size: width * scale)) } else if let bytes = ncData(item["src"]), let image = UIImage(data: bytes) { Image(uiImage: image).resizable().scaledToFit() } }.frame(width: width * scale, height: width / ratio * scale).rotationEffect(.degrees(item["rotation"] as? Double ?? 0)).position(x: x * scale, y: y * scale)
            }
            if !stickers.isEmpty { Text(stickers).font(.system(size: 40 * scale)).padding(.leading, 40 * scale).padding(.top, min(910, 150 + Double(text.count / 20) * 36) * scale) }
        }
    } }
}

private func ncDistance(_ a: NativePoint, _ b: NativePoint) -> Double {
    let p = Double.pi / 180, dLat = (b.lat - a.lat) * p, dLon = (b.lon - a.lon) * p
    let q = pow(sin(dLat / 2), 2) + cos(a.lat * p) * cos(b.lat * p) * pow(sin(dLon / 2), 2)
    return 12_742_000 * atan2(sqrt(max(0, q)), sqrt(max(0, 1 - q)))
}

@MainActor private struct NCDoodleEditor: View {
    @State private var failure: String?
    @ObservedObject var model: NativeAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var strokes: [[NativePoint]] = []
    @State private var drawing = true
    @State private var name = ""
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("地図の操作", selection: $drawing) { Text("指で描く").tag(true); Text("地図を動かす").tag(false) }.pickerStyle(.segmented).padding(12)
                NCDrawingMap(strokes: $strokes, drawing: drawing, center: model.currentPoint ?? model.walks.last?.points.first)
                HStack { TextField("らくがきの名前", text: $name); Button { if !strokes.isEmpty { strokes.removeLast() } } label: { Image(systemName: "arrow.uturn.backward") }.disabled(strokes.isEmpty).accessibilityLabel("ひとつ戻す") }.padding(16)
                Text("描いた線は、実際に歩いたところから消えていきます。位置情報がなくても地図を動かして描けます。").font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 12)
            }.navigationTitle("らくがきを描く").navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("保存") { save() }.disabled(strokes.allSatisfy { $0.count < 2 }) }
            }
        }.modifier(NCEditorError(model: model, failure: $failure))
    }
    private func save() {
        let points = strokes.filter { $0.count >= 2 }.flatMap { stroke in stroke.enumerated().map { index, point -> [String: Any] in var raw = point.json; raw["break"] = index == 0; return raw } }
        guard !points.isEmpty else { return }
        do { try model.updateLibrary { library in var items = library["doodles"] as? [[String: Any]] ?? []; items.append(["id": UUID().uuidString, "name": name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "らくがき" : ncText(name, utf16Limit: 60), "created": Date().timeIntervalSince1970 * 1000, "points": points]); library["doodles"] = items }; dismiss() } catch { failure = error.localizedDescription }
    }
}

@MainActor private struct NCDoodleDetail: View {
    @ObservedObject var model: NativeAppModel; let itemID: String
    @Environment(\.dismiss) private var dismiss
    @State private var deleting = false
    private var item: NCItem? { ncItems(model.library["doodles"]).first(where: { $0.id == itemID }) }
    private var strokes: [[NativePoint]] {
        var result: [[NativePoint]] = [], current: [NativePoint] = []
        for raw in item?.value["points"] as? [[String: Any]] ?? [] {
            guard let point = NativePoint(json: raw) else { continue }
            if point.isBreak || raw["done"] as? Bool == true { if !current.isEmpty { result.append(current); current = [] } }
            if raw["done"] as? Bool != true { current.append(point) }
        }
        if !current.isEmpty { result.append(current) }; return result
    }
    var body: some View {
        VStack(spacing: 18) {
            if strokes.isEmpty { NCEmptyView(symbol: "checkmark.circle", title: "歩いて描き終えました", detail: "このらくがきの線は、すべて歩いた記録になりました。") }
            else { NCDrawingMap(strokes: .constant(strokes), drawing: false, center: strokes.first?.first) }
            Text("残っている線を歩くと、白地図のらくがきが少しずつ消えます。").font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 20)
            Button("らくがきを削除", role: .destructive) { deleting = true }.padding(.bottom, 20)
        }.navigationTitle(item?.value["name"] as? String ?? "らくがき").navigationBarTitleDisplayMode(.inline).confirmationDialog("このらくがきを削除しますか？", isPresented: $deleting, titleVisibility: .visible) {
            Button("削除", role: .destructive) { do { try model.updateLibrary { library in library["doodles"] = (library["doodles"] as? [[String: Any]] ?? []).filter { $0["id"] as? String != itemID } }; dismiss() } catch { model.showError(error.localizedDescription) } }
        }
    }
}

private struct NCDrawingMap: UIViewRepresentable {
    @Binding var strokes: [[NativePoint]]
    let drawing: Bool
    let center: NativePoint?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(); map.delegate = context.coordinator; map.showsUserLocation = true; map.isRotateEnabled = false
        let initial = center.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) } ?? CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671)
        map.setRegion(MKCoordinateRegion(center: initial, latitudinalMeters: 1800, longitudinalMeters: 1800), animated: false)
        let gesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.draw(_:))); gesture.maximumNumberOfTouches = 1; gesture.delegate = context.coordinator; map.addGestureRecognizer(gesture); context.coordinator.gesture = gesture
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self; context.coordinator.gesture?.isEnabled = drawing; map.isScrollEnabled = !drawing
        let signature = strokes.map { "\($0.count):\($0.last?.lat ?? 0):\($0.last?.lon ?? 0)" }.joined(separator: "|")
        guard signature != context.coordinator.signature else { return }; context.coordinator.signature = signature
        map.removeOverlays(map.overlays)
        for stroke in strokes where stroke.count > 1 { let coordinates = stroke.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }; map.addOverlay(MKPolyline(coordinates: coordinates, count: coordinates.count)) }
    }
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: NCDrawingMap; weak var gesture: UIPanGestureRecognizer?; var signature = ""; var last: CGPoint?
        init(_ parent: NCDrawingMap) { self.parent = parent }
        @objc func draw(_ gesture: UIPanGestureRecognizer) {
            guard let map = gesture.view as? MKMapView, parent.drawing else { return }
            let location = gesture.location(in: map)
            if gesture.state == .began { guard parent.strokes.reduce(0, { $0 + $1.count }) < 10_000 else { return }; parent.strokes.append([]); last = nil }
            guard gesture.state == .began || gesture.state == .changed || gesture.state == .ended, !parent.strokes.isEmpty, parent.strokes.reduce(0, { $0 + $1.count }) < 10_000 else { return }
            if let last, hypot(location.x - last.x, location.y - last.y) < 3 { return }
            let coordinate = map.convert(location, toCoordinateFrom: map)
            guard CLLocationCoordinate2DIsValid(coordinate), abs(coordinate.latitude) <= 85 else { return }
            let index = parent.strokes.count - 1
            parent.strokes[index].append(NativePoint(lat: coordinate.latitude, lon: coordinate.longitude, isBreak: parent.strokes[index].isEmpty)); last = location
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer { guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }; let renderer = MKPolylineRenderer(polyline: line); renderer.strokeColor = UIColor.label.withAlphaComponent(0.65); renderer.lineWidth = 3; renderer.lineDashPattern = [5, 6]; return renderer }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    }
}

private struct NCAreaCoordinate: Sendable { let lat: Double; let lon: Double }
private struct NCArea: Identifiable, Sendable {
    let id: String; let name: String; let parent: String; let polygons: [[[NCAreaCoordinate]]]
    let minLat: Double; let maxLat: Double; let minLon: Double; let maxLon: Double
    func contains(_ p: NCAreaCoordinate) -> Bool {
        guard p.lat >= minLat, p.lat <= maxLat, p.lon >= minLon, p.lon <= maxLon else { return false }
        func ringContains(_ ring: [NCAreaCoordinate]) -> Bool {
            guard ring.count >= 3 else { return false }; var inside = false; var previous = ring.last!
            for current in ring { if (current.lat > p.lat) != (previous.lat > p.lat), p.lon < (previous.lon - current.lon) * (p.lat - current.lat) / (previous.lat - current.lat) + current.lon { inside.toggle() }; previous = current }; return inside
        }
        return polygons.contains { polygon in guard let outer = polygon.first, ringContains(outer) else { return false }; return !polygon.dropFirst().contains(where: ringContains) }
    }
}
private struct NCBadge: Identifiable, Sendable { let area: NCArea; var distance: Double = 0; var walkIDs = Set<String>(); var visited: [NCAreaCoordinate] = []; var id: String { area.id } }
private struct NCAreaTrack: Sendable { let id: String; let points: [NCAreaCoordinate]; let breaks: [Bool] }
private enum NCBadgeEngine {
    static func resource() -> URL? {
        #if PLAYGROUNDS
        let root = Bundle.module.url(forResource: "Web", withExtension: nil)
        #else
        let root = Bundle.main.url(forResource: "Web", withExtension: nil)
        #endif
        return root?.appendingPathComponent("data/japan-municipalities.geojson")
    }
    static func compute(tracks: [NCAreaTrack]) throws -> [NCBadge] {
        guard let resource = resource(), let root = try JSONSerialization.jsonObject(with: Data(contentsOf: resource)) as? [String: Any], let features = root["features"] as? [[String: Any]] else { throw NSError(domain: "PlainWalk", code: 1, userInfo: [NSLocalizedDescriptionKey: "エリアの境界データを読み込めませんでした。アプリを更新してお試しください。"] ) }
        var areas: [NCArea] = [], buckets: [String: [Int]] = [:]
        for feature in features {
            guard let properties = feature["properties"] as? [String: Any], let id = properties["id"] as? String, let geometry = feature["geometry"] as? [String: Any] else { continue }
            let raw: [[[[Double]]]]
            if geometry["type"] as? String == "Polygon", let polygon = geometry["coordinates"] as? [[[Double]]] { raw = [polygon] } else { raw = geometry["coordinates"] as? [[[[Double]]]] ?? [] }
            let polygons = raw.map { polygon in polygon.map { ring in ring.compactMap { p -> NCAreaCoordinate? in guard p.count >= 2 else { return nil }; return NCAreaCoordinate(lat: p[1], lon: p[0]) } } }
            let all = polygons.flatMap { $0.flatMap { $0 } }; guard !all.isEmpty else { continue }
            let area = NCArea(id: id, name: properties["name"] as? String ?? id, parent: properties["parent"] as? String ?? "", polygons: polygons, minLat: all.map(\.lat).min()!, maxLat: all.map(\.lat).max()!, minLon: all.map(\.lon).min()!, maxLon: all.map(\.lon).max()!)
            let index = areas.count; areas.append(area)
            for y in Int(floor(area.minLat * 5))...Int(floor(area.maxLat * 5)) { for x in Int(floor(area.minLon * 5))...Int(floor(area.maxLon * 5)) { buckets["\(x),\(y)", default: []].append(index) } }
        }
        var badges: [Int: NCBadge] = [:]; var visitedKeys: [Int: Set<String>] = [:]
        let perSegmentBudget = max(1, min(2000, 600_000 / max(1, tracks.reduce(0) { $0 + $1.points.count })))
        for track in tracks {
            for (index, point) in track.points.enumerated() {
                if Task.isCancelled { return [] }
                var samples: [(NCAreaCoordinate, Double)] = [(point, 0)]
                if index > 0, !track.breaks[index] {
                    let a = track.points[index - 1]; let distance = ncDistance(NativePoint(lat: a.lat, lon: a.lon), NativePoint(lat: point.lat, lon: point.lon))
                    let count = min(perSegmentBudget, max(1, Int(ceil(distance / 25))))
                    if distance <= 50_000 { samples = (1...count).map { i in let fraction = (Double(i) - 0.5) / Double(count); return (NCAreaCoordinate(lat: a.lat + (point.lat - a.lat) * fraction, lon: a.lon + (point.lon - a.lon) * fraction), distance / Double(count)) } }
                }
                for (sample, distance) in samples {
                    let key = "\(Int(floor(sample.lon * 5))),\(Int(floor(sample.lat * 5)))"
                    for areaIndex in buckets[key] ?? [] where areas[areaIndex].contains(sample) {
                        var badge = badges[areaIndex] ?? NCBadge(area: areas[areaIndex]); badge.distance += distance; badge.walkIDs.insert(track.id)
                        let cell = "\(Int(floor(sample.lon * cos((areas[areaIndex].minLat + areas[areaIndex].maxLat) * .pi / 360) * 111_320 / 500))),\(Int(floor(sample.lat * 111_320 / 500)))"
                        if visitedKeys[areaIndex, default: []].insert(cell).inserted { badge.visited.append(sample) }; badges[areaIndex] = badge
                    }
                }
            }
        }
        return badges.values.sorted { $0.distance > $1.distance }
    }
}
@MainActor private struct NCBadgesView: View {
    @ObservedObject var model: NativeAppModel
    @State private var badges: [NCBadge] = []; @State private var loading = false; @State private var failure: String?
    private var signature: String { model.walks.map { "\($0.id):\($0.points.count):\($0.end)" }.joined(separator: "|") }
    var body: some View {
        Group {
            if loading { ProgressView("歩いたエリアを調べています…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if let failure { ContentUnavailableView("エリアを読み込めません", systemImage: "exclamationmark.map", description: Text(failure)) }
            else if badges.isEmpty { NCEmptyView(symbol: "map", title: "まだバッジがありません", detail: "どこかを歩くと、最初のバッジがここに出ます。日本の市区町村の境界から記録を集計します。") }
            else { ScrollView { LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) { ForEach(badges) { badge in NavigationLink { VStack(spacing: 18) { NCBadgeImage(badge: badge).frame(height: 320); Text(badge.area.name).font(.title2.weight(.semibold)); Text(badge.area.parent).foregroundStyle(.secondary); Text("\(model.distanceText(badge.distance)) \(model.distanceUnit) ・ \(badge.walkIDs.count) 回のさんぽ"); Text("色のついた点は歩いた場所の目安です。境界は公開の市区町村データを使用しています。").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24); Spacer() }.navigationTitle("エリアバッジ").navigationBarTitleDisplayMode(.inline) } label: { VStack(spacing: 7) { NCBadgeImage(badge: badge).frame(height: 150); Text(badge.area.name).font(.subheadline.weight(.medium)); Text("\(model.distanceText(badge.distance)) \(model.distanceUnit)").font(.caption).foregroundStyle(.secondary) }.foregroundStyle(.primary).padding(12).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20)) }.buttonStyle(.plain) } }.padding(16) } }
        }.task(id: signature) { await load() }
    }
    private func load() async {
        guard !model.walks.isEmpty else { badges = []; loading = false; return }
        loading = true; failure = nil
        let tracks = model.walks.map { NCAreaTrack(id: $0.id, points: $0.points.map { NCAreaCoordinate(lat: $0.lat, lon: $0.lon) }, breaks: $0.points.map(\.isBreak)) }
        let worker = Task.detached(priority: .userInitiated) { try NCBadgeEngine.compute(tracks: tracks) }
        do { let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() }); guard !Task.isCancelled else { return }; badges = result; loading = false } catch { guard !Task.isCancelled else { return }; failure = error.localizedDescription; loading = false }
    }
}
private struct NCBadgeImage: View {
    let badge: NCBadge
    var body: some View { Canvas { context, size in
        let area = badge.area, cosine = cos((badge.area.minLat + badge.area.maxLat) * .pi / 360)
        let scale = max(max((area.maxLon - area.minLon) * cosine / max(1, size.width - 24), (area.maxLat - area.minLat) / max(1, size.height - 24)), 0.00000001)
        func p(_ coordinate: NCAreaCoordinate) -> CGPoint { CGPoint(x: (coordinate.lon - (area.minLon + area.maxLon) / 2) * cosine / scale + size.width / 2, y: size.height / 2 - (coordinate.lat - (area.minLat + area.maxLat) / 2) / scale) }
        var boundary = Path(); for polygon in area.polygons { for ring in polygon { guard let first = ring.first else { continue }; boundary.move(to: p(first)); for point in ring.dropFirst() { boundary.addLine(to: p(point)) }; boundary.closeSubpath() } }
        context.fill(boundary, with: .color(Color(uiColor: .tertiarySystemFill)), style: FillStyle(eoFill: true)); context.stroke(boundary, with: .color(.secondary.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
        var clipped = context; clipped.clip(to: boundary, style: FillStyle(eoFill: true))
        let radius = max(2.5, min(10, (500 / 111_320) / scale / 2))
        for point in badge.visited { let center = p(point); clipped.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(Color.primary.opacity(0.7))) }
    }.accessibilityLabel(badge.area.name + "の歩いたエリア") }
}
