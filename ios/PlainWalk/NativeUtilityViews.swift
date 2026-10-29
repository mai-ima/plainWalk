import SwiftUI
import Combine

@MainActor struct NativeMenuView: View {
    @ObservedObject var model: NativeAppModel
    @State private var discard = false
    var body: some View {
        NavigationStack {
            List {
                if model.isRecording || model.isPaused {
                    Section("さんぽ") {
                        Label(model.isRecording ? "記録中" : "一時停止中", systemImage: "shoeprints.fill")
                        Button(model.isRecording ? "一時停止" : "再開", action: model.togglePause)
                        Button("保存して終了", action: model.finishRecording)
                        Button("記録を破棄", role: .destructive) { discard = true }
                    }
                }
                Section {
                    Button { model.openAnswerMap() } label: { Label("答え合わせマップ", systemImage: "map") }
                    Button { model.openLayers() } label: { Label("地図レイヤー", systemImage: "square.3.layers.3d") }
                    Button { model.openStats() } label: { Label("歩行の記録", systemImage: "chart.bar") }
                    Button { model.openReplay() } label: { Label("軌跡を再生", systemImage: "play") }
                }
                Section {
                    ForEach(NativeCollection.allCases) { item in
                        Button(item.title) { model.openCollection(item) }
                    }
                }
                Section {
                    Button { model.openSettings() } label: { Label("設定", systemImage: "gearshape") }
                    Button { model.present(.developer) } label: { Label("実機検証", systemImage: "wrench.and.screwdriver") }
                }
            }
            .navigationTitle("メニュー").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる", action: model.closeSheet) } }
            .confirmationDialog("この記録を破棄しますか？", isPresented: $discard, titleVisibility: .visible) {
                Button("破棄", role: .destructive, action: model.discardRecording)
            }
        }
    }
}

@MainActor struct NativeStatsView: View {
    @ObservedObject var model: NativeAppModel
    private var distance: Double { model.walks.reduce(0) { $0 + $1.distance } }
    private var seconds: Double { model.walks.reduce(0) { $0 + $1.duration } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("さんぽの回数", value: "\(model.walks.count) 回")
                    LabeledContent("歩いた距離", value: model.distanceText(distance) + " " + model.distanceUnit)
                    LabeledContent("開拓した道", value: model.distanceText(model.totalPioneered) + " " + model.distanceUnit)
                    LabeledContent("歩いた時間", value: NativeRecordDates.duration(seconds))
                }
                Section("最近のさんぽ") {
                    ForEach(model.walks.prefix(30)) { walk in
                        Button { model.openWalk(walk.id) } label: { recentWalk(walk) }
                    }
                }
            }
            .navigationTitle("歩行の記録").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる", action: model.closeSheet) } }
        }
    }
    private func recentWalk(_ walk: NativeWalk) -> some View {
        HStack {
            NativeTrailThumbnail(points: walk.points, color: model.ink, lineWidth: 2).frame(width: 65, height: 55)
            VStack(alignment: .leading) {
                Text(walk.name.isEmpty ? "さんぽ" : walk.name).foregroundStyle(.primary)
                Text(Date(timeIntervalSince1970: walk.start / 1000), style: .date).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(model.distanceText(walk.distance) + " " + model.distanceUnit).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}

@MainActor struct NativeReplayView: View {
    @ObservedObject var model: NativeAppModel
    let walkID: String?
    @State private var progress = 1.0
    @State private var playing = false
    @State private var points: [NativePoint] = []
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if points.isEmpty {
                    ContentUnavailableView("まだ軌跡がありません", systemImage: "shoeprints.fill", description: Text("さんぽを記録すると、道を描いた順に振り返れます。"))
                } else {
                    NativeTrailThumbnail(points: Array(points.prefix(max(1, Int(Double(points.count) * progress)))), color: model.ink, lineWidth: 2.5)
                        .padding(32).frame(maxHeight: .infinity).background(model.paper)
                        .accessibilityElement(children: .ignore).accessibilityLabel("さんぽの軌跡")
                        .accessibilityValue("\(Int(progress * 100))パーセント")
                    Slider(value: $progress, in: 0...1) { editing in if editing { playing = false } }
                        .accessibilityLabel("再生位置")
                    Button {
                        if progress >= 1 { progress = 0 }
                        playing.toggle()
                    } label: {
                        Label(playing ? "一時停止" : "再生", systemImage: playing ? "pause.fill" : "play.fill")
                            .font(.headline).padding(16).frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(.primary)
                }
            }
            .padding().navigationTitle("軌跡を再生").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる", action: model.closeSheet) } }
            .onReceive(timer) { _ in
                guard playing else { return }
                progress = min(1, progress + 0.05 / 20)
                if progress >= 1 { playing = false }
            }
            .onAppear(perform: preparePoints)
            .onChange(of: model.libraryRevision) { _, _ in preparePoints() }
            .onDisappear { playing = false }
        }
    }
    private func preparePoints() {
        let walks = walkID.map { id in model.walks.filter { $0.id == id } } ?? model.walks.sorted { $0.start < $1.start }
        let count = walks.reduce(0) { $0 + $1.points.count }
        let stride = max(1, Int(ceil(Double(count) / 4000)))
        var result: [NativePoint] = []
        var index = 0
        var disconnected = true
        for walk in walks {
            disconnected = true
            for (localIndex, raw) in walk.points.enumerated() {
                if raw.isBreak { disconnected = true }
                if index % stride == 0 || localIndex == walk.points.count - 1 {
                    var point = raw
                    point.isBreak = disconnected
                    result.append(point)
                    disconnected = false
                }
                index += 1
            }
        }
        points = result
    }
}

@MainActor struct NativeHealthImportView: View {
    @ObservedObject var model: NativeAppModel
    @State private var workouts: [[String: Any]] = []
    @State private var busy = true
    @State private var importingID: String?
    @State private var notice: String?
    var body: some View {
        NavigationStack {
            List {
                if busy {
                    ProgressView("ワークアウトを読み込み中")
                } else if workouts.isEmpty {
                    ContentUnavailableView("ルートを選べません", systemImage: "heart.text.square", description: Text(notice ?? "屋外ワークアウトがありません。読み取りの許可も確認してください。"))
                } else {
                    ForEach(Array(workouts.enumerated()), id: \.offset) { _, item in
                        Button { importWorkout(item) } label: { workoutLabel(item) }.disabled(importingID != nil)
                    }
                }
            }
            .navigationTitle("ワークアウトを取り込む").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる", action: model.closeSheet) } }
            .task {
                do { workouts = try await HealthService().workouts() }
                catch { notice = error.localizedDescription }
                busy = false
            }
            .alert("取り込み", isPresented: Binding(get: { notice != nil && !workouts.isEmpty }, set: { if !$0 { notice = nil } })) {
                Button("閉じる") { notice = nil }
            } message: { Text(notice ?? "") }
        }
    }
    private func workoutLabel(_ item: [String: Any]) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(workoutTitle(item["kind"] as? String))
                Text(Date(timeIntervalSince1970: (nativeNumber(item["start"]) ?? 0) / 1000), style: .date)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if importingID == (item["id"] as? String) { ProgressView() }
            else { Image(systemName: "square.and.arrow.down") }
        }
    }
    private func workoutTitle(_ kind: String?) -> String {
        switch kind { case "running": return "ランニング"; case "cycling": return "サイクリング"; default: return "さんぽ" }
    }
    private func importWorkout(_ item: [String: Any]) {
        guard importingID == nil, let id = item["id"] as? String else { return }
        importingID = id
        Task {
            defer { importingID = nil }
            do {
                var route = try await HealthService().route(id: id)
                guard route.count >= 2 else { throw NativeError.message("このワークアウトにはルートがありません。") }
                for i in route.indices { route[i]["mode"] = item["kind"] ?? "walking" }
                var walk = item
                walk["points"] = route
                walk["name"] = "ヘルスケアのさんぽ"
                walk["duration"] = (nativeNumber(item["duration"]) ?? 0) * 1000
                try model.updateLibrary { data in
                    var list = data["walks"] as? [[String: Any]] ?? []
                    if !list.contains(where: { ($0["id"] as? String) == id }) { list.append(walk) }
                    data["walks"] = list
                }
                notice = "さんぽを取り込みました。"
            } catch { notice = error.localizedDescription }
        }
    }
}
