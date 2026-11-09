import SwiftUI
import MapKit

@MainActor struct NativeAnswerMapView: View {
    @ObservedObject var model: NativeAppModel
    @State private var satellite = false
    @State private var pitched = false
    @State private var query = ""
    @State private var results: [NativeAnswerResult] = []
    @State private var selected: NativeAnswerPlace?
    @State private var searching = false
    @State private var showingSearch = false
    @State private var showingDoodle = false
    @State private var searchError: String?
    @State private var activeSearch: MKLocalSearch?
    @State private var searchRegion = MKCoordinateRegion(center: .init(latitude: 36.5, longitude: 137.2), span: .init(latitudeDelta: 16, longitudeDelta: 16))
    @State private var focusRevision = 0
    @State private var locateRevision = 0
    @State private var zoomRevision = 0
    @State private var zoomIn = true
    #if DEBUG
    @State private var captureMode: String? = nil
    #endif

    var body: some View {
        ZStack {
            NativeAnswerMapSurface(walks: model.walks, activePoints: model.activePoints, libraryRevision: model.libraryRevision,
                flags: model.flags, current: model.currentPoint, satellite: satellite, pitched: pitched,
                focus: selected, focusRevision: focusRevision, locateRevision: locateRevision,
                zoomRevision: zoomRevision, zoomIn: zoomIn,
                onRegion: { searchRegion = $0 }, onPick: select)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                HStack { Spacer(); controls }.padding(.bottom, 18)
                if let selected { selectionCard(selected).padding(.bottom, 12) }
                bottomActions
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
        }
        .sheet(isPresented: $showingSearch, onDismiss: cancelSearch) { searchSheet }
        .sheet(isPresented: $showingDoodle) {
            NCDoodleEditor(initialCenter:NativePoint(lat:min(85,max(-85,searchRegion.center.latitude)),lon:searchRegion.center.longitude),model:model)
        }
        .onDisappear(perform: cancelSearch)
    }

    private var header: some View {
        ZStack {
            Text("答え合わせマップ").font(.system(size: 18, weight: .semibold))
                .padding(.horizontal, 86).lineLimit(1).minimumScaleFactor(0.7)
            HStack {
                Spacer()
                Button { model.closeSheet() } label: {
                    Text("閉じる").font(.system(size: 17, weight: .medium))
                        .padding(.horizontal, 18).frame(height: 44)
                        .background(.regularMaterial, in: Capsule())
                }.buttonStyle(.plain).accessibilityLabel("答え合わせマップを閉じる")
            }
        }
        .frame(minHeight: 44).foregroundStyle(.primary)
    }
    private var bottomActions: some View {
        HStack(spacing: 10) {
            Button { model.haptic(); showingSearch = true } label: {
                Label("目的地を決める", systemImage: "flag")
                    .padding(.horizontal, 18).frame(minHeight: 44)
                    .background(Color.black, in: Capsule()).foregroundStyle(.white)
            }.accessibilityHint("場所を検索します。地図の長押しでも選べます。")
            Button { model.haptic(); showingDoodle = true } label: {
                Label("らくがき", systemImage: "pencil.tip")
                    .padding(.horizontal, 18).frame(minHeight: 44)
                    .background(.regularMaterial, in: Capsule()).foregroundStyle(.primary)
            }
        }
        .font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
        .buttonStyle(.plain).frame(maxWidth: .infinity)
    }
    private var controls: some View {
        VStack(spacing: 14) {
            Menu {
                Picker("地図の表示", selection: $satellite) {
                    Text("標準地図").tag(false)
                    Text("航空写真").tag(true)
                }
                Toggle("3D 表示", isOn: $pitched)
                Divider()
                Button { zoomIn = true; zoomRevision += 1; model.haptic() } label: { Label("地図を拡大", systemImage: "plus.magnifyingglass") }
                Button { zoomIn = false; zoomRevision += 1; model.haptic() } label: { Label("地図を縮小", systemImage: "minus.magnifyingglass") }
            } label: {
                Image(systemName: "square.3.layers.3d").font(.system(size: 25))
                    .frame(width: 54, height: 54).background(.regularMaterial, in: Circle())
            }.accessibilityLabel("地図レイヤー").accessibilityHint("標準地図、航空写真、3D、拡大・縮小を選べます。")
            mapButton("現在地", symbol: "scope") { model.locate(); locateRevision += 1 }
        }.foregroundStyle(.primary).shadow(color: .black.opacity(0.08), radius: 10, y: 5)
    }
    private func mapButton(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button { model.haptic(); action() } label: { Image(systemName: symbol).font(.system(size: 25)).frame(width: 54, height: 54).background(.regularMaterial, in: Circle()) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }
    private var searchSheet: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "mappin.and.ellipse").font(.system(size: 42)).foregroundStyle(.tertiary)
                        Text("行ってみたい場所を探す").font(.headline)
                        Text("場所の名前や住所を入力してください。\n地図を長押しして目的地を選ぶこともできます。")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else { searchResults.frame(maxHeight: .infinity, alignment: .top) }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("目的地を決める").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { showingSearch = false } } }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "場所や住所を検索")
            .task(id: query) { await search() }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .onAppear { captureSearchSheetRequested() }
    }
    private func cancelSearch() {
        activeSearch?.cancel(); activeSearch = nil
        query = ""; results = []; searching = false; searchError = nil
    }
    private var searchResults: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if searching { HStack { ProgressView(); Text("場所を探しています").font(.subheadline).foregroundStyle(.secondary) }.padding(16) }
                else if let searchError { Text(searchError).font(.subheadline).foregroundStyle(.secondary).padding(16) }
                else if results.isEmpty { Text("場所が見つかりませんでした。別の名前や住所で探してください。").font(.subheadline).foregroundStyle(.secondary).padding(16) }
                ForEach(results) { result in
                    Button {
                        select(result.place)
                        showingSearch = false
                        query = ""
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle").font(.title2).foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 4) { Text(result.place.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary); if !result.subtitle.isEmpty { Text(result.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2) } }
                            Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.padding(16).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if result.id != results.last?.id { Divider().padding(.leading, 52) }
                }
            }
        }.frame(maxHeight: 300).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22)).padding(12)
    }
    private func selectionCard(_ place: NativeAnswerPlace) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text(place.name).font(.headline).lineLimit(2); Text("白地図に旗を立て、現在地からの方向を表示します。").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button { selected = nil } label: { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary).frame(width: 44, height: 44) }.accessibilityLabel("場所の選択を解除")
            }
            HStack(spacing: 12) {
                Button { navigate(place) } label: { Label("ここへ向かう", systemImage: "flag.fill").frame(maxWidth: .infinity).padding(.vertical, 4) }.buttonStyle(.borderedProminent).tint(.primary)
                Button { bookmark(place) } label: { Image(systemName: "bookmark").frame(width: 36, height: 36) }.buttonStyle(.bordered).accessibilityLabel("気になる場所に保存")
            }
        }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
    private func select(_ place: NativeAnswerPlace) { selected = place; focusRevision += 1; model.haptic() }
    private func navigate(_ place: NativeAnswerPlace) {
        let flag = NativeFlag(id: UUID().uuidString, name: place.name, point: NativePoint(lat: place.lat, lon: place.lon))
        do {
            try model.updateLibrary { library in var flags = library["flags"] as? [[String: Any]] ?? []; flags.insert(flag.json, at: 0); library["flags"] = flags }
            model.navigateToFlag(flag)
        } catch { model.showError(error.localizedDescription) }
    }
    private func bookmark(_ place: NativeAnswerPlace) {
        var value = NativePoint(lat: place.lat, lon: place.lon).json
        value["id"] = UUID().uuidString; value["name"] = place.name
        do { try model.updateLibrary { library in var places = library["bookmarks"] as? [[String: Any]] ?? []; places.append(value); library["bookmarks"] = places }; model.haptic(); selected = nil }
        catch { model.showError(error.localizedDescription) }
    }
    private func search() async {
        #if DEBUG
        if captureMode == "answerSearch",ProcessInfo.processInfo.arguments.contains("-PlainWalkScreenshotFixture") {
            activeSearch?.cancel();activeSearch=nil;searching=false
            results=Self.capturePlace(model).map { [NativeAnswerResult(id:"capture-saved-place",place:$0,subtitle:"合成データ（実際の検索結果ではありません）")] } ?? []
            searchError=results.isEmpty ? "検証用のしおりデータがありません。" : nil
            return
        }
        #endif
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        activeSearch?.cancel(); activeSearch = nil
        results = []; searchError = nil
        guard !text.isEmpty else { searching = false; return }
        searching = true
        do {
            try await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let request = MKLocalSearch.Request(); request.naturalLanguageQuery = text; request.region = searchRegion
            let localSearch = MKLocalSearch(request: request); activeSearch = localSearch
            let response = try await localSearch.start()
            guard !Task.isCancelled else { return }
            results = response.mapItems.compactMap { item in
                let c = item.placemark.coordinate
                guard CLLocationCoordinate2DIsValid(c), abs(c.latitude) <= 85 else { return nil }
                return NativeAnswerResult(id: UUID().uuidString, place: .init(name: item.name ?? "選んだ場所", lat: c.latitude, lon: c.longitude), subtitle: item.placemark.title ?? "")
            }
            searching = false
        } catch {
            guard !Task.isCancelled else { return }
            searching = false; searchError = "検索できませんでした。通信状態を確認して、もう一度お試しください。"
        }
    }


    private func captureSearchSheetRequested() {
        #if DEBUG
        guard captureMode == "answerSearch",ProcessInfo.processInfo.arguments.contains("-PlainWalkScreenshotFixture") else {return}
        // This is a presentation request marker, not proof that the modal is
        // visible. The capture runner separately verifies its displayed title.
        let folder=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("PlainWalk",isDirectory:true)
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        try? Data("answerSearch".utf8).write(to:folder.appendingPathComponent("capture-dialog.ready"),options:.atomic)
        #endif
    }

#if DEBUG
    /// Verify committed MapKit camera state, rather than waiting for tiles or
    /// accepting a screenshot whose controls rendered over a wrong viewport.
    static func cameraSelfTest() async throws -> Bool {
        func require(_ condition: @autoclosure () -> Bool, _ name: String) throws {
            guard condition() else { throw NativeError.message("答え合わせマップのカメラ検証に失敗: " + name) }
        }
        typealias Harness = (map: MKMapView, coordinator: NativeAnswerMapSurface.Coordinator, surface: NativeAnswerMapSurface)
        let controller = UIViewController()
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 320, height: 600)
        } else { window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 600)) }
        window.rootViewController = controller
        // Do not replace the application's key window or request any location
        // permission. The temporary host only lets MapKit commit its layout.
        window.isHidden = false
        var retained: [(MKMapView, NativeAnswerMapSurface.Coordinator)] = []
        defer {
            for (map, coordinator) in retained { map.delegate = nil; coordinator.cancelCameraChanges(); coordinator.map = nil }
            window.isHidden = true
        }
        func configuredMap(walks: [NativeWalk] = [], current: NativePoint? = nil,
                           pitched: Bool = false, focus: NativeAnswerPlace? = nil, zoom: Bool = false) -> Harness {
            controller.view.subviews.forEach { $0.removeFromSuperview() }
            let map = MKMapView(frame: controller.view.bounds)
            map.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            controller.view.addSubview(map)
            let surface = NativeAnswerMapSurface(walks: walks, activePoints: [], libraryRevision: 0,
                flags: [], current: current, satellite: false, pitched: pitched,
                focus: focus, focusRevision: focus == nil ? 0 : 1, locateRevision: 0, zoomRevision: zoom ? 1 : 0, zoomIn: true,
                onRegion: { _ in }, onPick: { _ in })
            let coordinator = NativeAnswerMapSurface.Coordinator(surface)
            retained.append((map, coordinator))
            coordinator.map = map; map.delegate = coordinator
            map.setRegion(.init(center: .init(latitude: 36.5, longitude: 137.2), span: .init(latitudeDelta: 16, longitudeDelta: 16)), animated: false)
            coordinator.update(surface, map: map)
            map.layoutIfNeeded()
            return (map, coordinator, surface)
        }
        func settle(_ harness: Harness, _ name: String) async throws {
            let deadline = ProcessInfo.processInfo.systemUptime + 5
            while ProcessInfo.processInfo.systemUptime < deadline {
                harness.map.layoutIfNeeded()
                let expectedPitch: CGFloat = harness.surface.pitched ? 55 : 0
                if harness.coordinator.cameraChangesSettled && abs(harness.map.camera.pitch - expectedPitch) < 1 { return }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            let camera = harness.map.camera
            throw NativeError.message("答え合わせマップのカメラ確定を確認できません: \(name), center=\(camera.centerCoordinate.latitude),\(camera.centerCoordinate.longitude), distance=\(camera.centerCoordinateDistance), pitch=\(camera.pitch)")
        }
        func near(_ map: MKMapView, _ coordinate: CLLocationCoordinate2D, meters: Double = 250) -> Bool {
            MKMapPoint(map.camera.centerCoordinate).distance(to: MKMapPoint(coordinate)) < meters
        }
        func distanceRatio(_ map: MKMapView, _ distance: Double) -> Double { map.camera.centerCoordinateDistance / distance }
        func contains(_ map: MKMapView, _ point: NativePoint) -> Bool {
            let rect = map.visibleMapRect, projected = MKMapPoint(CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon))
            let x = NativeMapProjection.nearest(projected.x, to: rect.midX, period: MKMapRect.world.width)
            return rect.contains(MKMapPoint(x: x, y: projected.y))
        }

        let empty = configuredMap()
        try await settle(empty, "空データ・平面")
        try require((30...45).contains(empty.map.region.center.latitude) && (125...150).contains(empty.map.region.center.longitude), "空データで日本を表示")
        try require(empty.map.region.span.latitudeDelta > 5, "空データで地域全体を表示")
        try require(abs(empty.map.camera.pitch) < 0.1, "初期表示は平面")

        let point = NativePoint(lat: 35.6812, lon: 139.7671, t: 1_000)
        let coordinate = CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
        let geometry = MKMapCamera(lookingAtCenter: coordinate, fromDistance: 1_500, pitch: 55, heading: 27)
        try require(abs(geometry.pitch - 55) < 0.1 && abs(geometry.centerCoordinateDistance - 1_500) < 1
            && abs(geometry.heading - 27) < 0.1, "距離・傾斜・方位を同時に指定したカメラの幾何を保持（角度 \(geometry.pitch)、距離 \(geometry.centerCoordinateDistance)、方位 \(geometry.heading)）")
        var located = configuredMap(current: point)
        try await settle(located, "GPS・平面")
        try require(near(located.map, coordinate), "初回の平面設定でGPS中心を保持")
        try require(located.map.region.span.latitudeDelta < 0.1, "GPSの表示倍率を保持")
        let flatDistance = located.map.camera.centerCoordinateDistance
        do {
            // An identical locate request need not produce a MapKit delegate
            // callback. Verify acknowledgement from the committed viewport.
            located.map.delegate = nil
            defer { located.map.delegate = located.coordinator }
            located.surface.locateRevision += 1; located.coordinator.update(located.surface, map: located.map)
            try await settle(located, "同じ現在地を再指定・callbackなし")
            try require(near(located.map, coordinate) && (0.99...1.01).contains(distanceRatio(located.map, flatDistance)), "同じ現在地の再指定で中心と倍率を保持")
            try require(abs(located.map.camera.pitch) < 0.1, "同じ現在地の再指定で平面を保持")
        }
        located.surface.pitched = true; located.coordinator.update(located.surface, map: located.map)
        try await settle(located, "平面から3D")
        try require(near(located.map, coordinate) && (0.9...1.1).contains(distanceRatio(located.map, flatDistance)), "3D切り替えで中心と倍率を保持（距離比 \(distanceRatio(located.map, flatDistance))、中心 \(located.map.camera.centerCoordinate.latitude),\(located.map.camera.centerCoordinate.longitude)）")
        try require(abs(located.map.camera.pitch - 55) < 1, "3Dの角度を適用（角度 \(located.map.camera.pitch)、距離 \(located.map.camera.centerCoordinateDistance)、高度 \(located.map.camera.altitude)）")
        let beforeZoom = located.map.camera.centerCoordinateDistance
        located.surface.zoomRevision += 1; located.coordinator.update(located.surface, map: located.map)
        try await settle(located, "3Dで拡大")
        try require(near(located.map, coordinate) && (0.4...0.6).contains(distanceRatio(located.map, beforeZoom)), "3Dで拡大しても中心と角度を保持")
        try require(abs(located.map.camera.pitch - 55) < 1, "拡大後も3Dを保持")
        located.surface.zoomIn = false; located.surface.zoomRevision += 1; located.coordinator.update(located.surface, map: located.map)
        try await settle(located, "3Dで縮小して倍率を戻す")
        try require(near(located.map, coordinate) && (0.9...1.1).contains(distanceRatio(located.map, beforeZoom)), "3Dで拡大・縮小して元の中心と倍率を保持")
        try require(abs(located.map.camera.pitch - 55) < 1, "縮小後も3Dを保持（角度 \(located.map.camera.pitch)）")

        let initial3D = configuredMap(current: point, pitched: true)
        try await settle(initial3D, "初回からGPS・3D")
        try require(near(initial3D.map, coordinate) && (0.9...1.1).contains(distanceRatio(initial3D.map, flatDistance)), "初回3DでGPS中心と倍率を保持")
        try require(abs(initial3D.map.camera.pitch - 55) < 1, "初回3Dの角度を適用")

        let points = [NativePoint(lat: 34.68, lon: 135.50, t: 1_000), NativePoint(lat: 34.69, lon: 135.52, t: 11_000)]
        func walk(_ points: [NativePoint]) throws -> NativeWalk {
            guard let result = NativeWalk(json: ["id": "camera-self-test", "name": "camera", "start": 1_000.0, "end": 11_000.0, "points": points.map(\.json)]) else {
                throw NativeError.message("カメラ検証用の軌跡を生成できません。")
            }
            return result
        }
        let trail = try walk(points)
        let routed = configuredMap(walks: [trail])
        try await settle(routed, "軌跡・平面")
        try require(points.allSatisfy { contains(routed.map, $0) }, "初回の平面設定で軌跡全体を保持")
        try require(abs(routed.map.region.center.latitude - 34.685) < 0.05 && abs(routed.map.region.center.longitude - 135.51) < 0.05, "軌跡の中心を保持")
        try require(routed.map.region.span.latitudeDelta < 0.2, "軌跡の表示倍率を保持")
        let trailDistance = routed.map.camera.centerCoordinateDistance
        let routed3D = configuredMap(walks: [trail], pitched: true)
        try await settle(routed3D, "初回から軌跡・3D")
        try require(near(routed3D.map, routed.map.camera.centerCoordinate, meters: 100) && (0.9...1.1).contains(distanceRatio(routed3D.map, trailDistance)), "初回3Dで軌跡中心と倍率を保持")
        try require(points.allSatisfy { contains(routed3D.map, $0) }, "初回3Dで軌跡が表示範囲に残る")

        let focus = NativeAnswerPlace(name: "カメラ検証", lat: 35.0116, lon: 135.7681)
        let focused = configuredMap(current: point, focus: focus)
        try await settle(focused, "初期フォーカス")
        let focusDistance = focused.map.camera.centerCoordinateDistance
        var focused3D = configuredMap(current: point, pitched: true, focus: focus, zoom: true)
        try await settle(focused3D, "初回3D・フォーカス・拡大の同時更新")
        try require(near(focused3D.map, focus.coordinate) && (0.4...0.6).contains(distanceRatio(focused3D.map, focusDistance)), "初回3Dのフォーカスと倍率を保持")
        try require(abs(focused3D.map.camera.pitch - 55) < 1, "フォーカス後も3Dを保持")
        let beforeFlat = focused3D.map.camera.centerCoordinateDistance
        focused3D.surface.pitched = false; focused3D.coordinator.update(focused3D.surface, map: focused3D.map)
        try await settle(focused3D, "フォーカス後に平面")
        try require(near(focused3D.map, focus.coordinate) && (0.9...1.1).contains(distanceRatio(focused3D.map, beforeFlat)), "平面へ戻してもフォーカスと倍率を保持")

        let crossing = [NativePoint(lat: 0.01, lon: 179.9999, t: 1_000), NativePoint(lat: 0.0101, lon: -179.9999, t: 11_000)]
        let crossingMap = configuredMap(walks: [try walk(crossing)])
        try await settle(crossingMap, "日付変更線の軌跡")
        try require(abs(crossingMap.map.camera.centerCoordinate.longitude) > 179, "日付変更線の近くに中心を保持")
        try require(crossingMap.map.region.span.longitudeDelta < 1 && crossing.allSatisfy { contains(crossingMap.map, $0) }, "日付変更線を跨ぐ軌跡を局所的に表示")
        let lines = crossingMap.map.overlays.compactMap { $0 as? MKPolyline }
        try require(lines.count == 1, "日付変更線を跨ぐ連続区間を保持")
        let expectedWidth = MKMapRect.world.width * 0.0002 / 360
        try require(abs(lines[0].boundingMapRect.width - expectedWidth) < 1, "22mの軌跡overlayを世界幅にしない")
        let pixels = crossing.map { crossingMap.map.convert(CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon), toPointTo: crossingMap.map) }
        try require(pixels.allSatisfy { $0.x.isFinite && $0.x >= 0 && $0.x <= crossingMap.map.bounds.width }
            && abs(pixels[0].x - pixels[1].x) < crossingMap.map.bounds.width, "日付変更線の軌跡overlayと画面座標を同じworldコピーに表示")
        return true
    }
#endif
}

private struct NativeAnswerPlace: Equatable { var name: String; var lat: Double; var lon: Double; var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) } }
private struct NativeAnswerResult: Identifiable { var id: String; var place: NativeAnswerPlace; var subtitle: String }

@MainActor private struct NativeAnswerMapSurface: UIViewRepresentable {
    var walks: [NativeWalk]; var activePoints: [NativePoint]; var libraryRevision: Int
    var flags: [NativeFlag]; var current: NativePoint?; var satellite: Bool; var pitched: Bool
    var focus: NativeAnswerPlace?; var focusRevision: Int; var locateRevision: Int; var zoomRevision: Int; var zoomIn: Bool
    var onRegion: (MKCoordinateRegion) -> Void; var onPick: (NativeAnswerPlace) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(); map.delegate = context.coordinator
        #if DEBUG
        map.showsUserLocation = !ProcessInfo.processInfo.arguments.contains("-PlainWalkScreenshotFixture")
        #else
        map.showsUserLocation = true
        #endif
        map.showsCompass = false; map.showsBuildings = true; map.isPitchEnabled = true; map.isRotateEnabled = true
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "destination")
        let scale = MKScaleView(mapView: map); scale.scaleVisibility = .adaptive; scale.translatesAutoresizingMaskIntoConstraints = false
        let compass = MKCompassButton(mapView: map); compass.compassVisibility = .adaptive; compass.translatesAutoresizingMaskIntoConstraints = false
        map.addSubview(scale); map.addSubview(compass)
        NSLayoutConstraint.activate([
            scale.leadingAnchor.constraint(equalTo: map.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            scale.topAnchor.constraint(equalTo: map.safeAreaLayoutGuide.topAnchor, constant: 66),
            compass.trailingAnchor.constraint(equalTo: map.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            compass.topAnchor.constraint(equalTo: map.safeAreaLayoutGuide.topAnchor, constant: 66)
        ])
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pick(_:))); longPress.minimumPressDuration = 0.65
        map.addGestureRecognizer(longPress)
        map.setRegion(MKCoordinateRegion(center: .init(latitude: 36.5, longitude: 137.2), span: .init(latitudeDelta: 16, longitudeDelta: 16)), animated: false)
        context.coordinator.map = map
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) { context.coordinator.update(self, map: map) }
    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) { map.delegate = nil; coordinator.cancelCameraChanges(); coordinator.map = nil }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: NativeAnswerMapSurface
        weak var map: MKMapView?
        private var savedRevision = -1
        private var activeKey = ""
        private var savedLines: [MKPolyline] = []
        private var activeLines: [MKPolyline] = []
        private var flagKey = ""
        private var focusedRevision = 0
        private var locatedRevision = 0
        private var zoomedRevision = 0
        private var satellite: Bool?
        private var pitched: Bool?
        private var pendingPitch = false
        private var awaitingViewport = false
        private var committingCamera: MKMapCamera?
        private var pendingZoom = 1.0
        private var cameraWork: DispatchWorkItem?
        private var viewportCenter: CLLocationCoordinate2D?
        private var viewportRadius: CLLocationDistance = 0
        private var animateCamera = false
        private var initialized = false
        private var waitingForFix = false
        private var focusPin: MKPointAnnotation?
        init(_ parent: NativeAnswerMapSurface) { self.parent = parent }
        func update(_ next: NativeAnswerMapSurface, map: MKMapView) {
            parent = next
            if satellite != next.satellite {
                satellite = next.satellite
                if next.satellite { map.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .realistic) }
                else { map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .realistic) }
            }
            if savedRevision != next.libraryRevision {
                savedRevision = next.libraryRevision; map.removeOverlays(savedLines)
                savedLines = next.walks.flatMap { Self.lines($0.points, active: false) }; map.addOverlays(savedLines)
            }
            let key = "\(next.activePoints.count):\(next.activePoints.last?.t ?? 0)"
            if activeKey != key { activeKey = key; map.removeOverlays(activeLines); activeLines = Self.lines(next.activePoints, active: true); map.addOverlays(activeLines) }
            let flagsKey = next.flags.map { "\($0.id):\($0.name):\($0.point.lat):\($0.point.lon)" }.joined(separator: ";")
            if flagKey != flagsKey {
                flagKey = flagsKey; map.removeAnnotations(map.annotations.filter { $0 is NativeAnswerFlagAnnotation })
                map.addAnnotations(next.flags.map(NativeAnswerFlagAnnotation.init))
            }
            if !initialized {
                initialized = true
                if let current = next.current { locate(current, map: map, animated: false) }
                else if !savedLines.isEmpty, let rect = Self.fitRect(next.walks) {
                    let center = MKMapPoint(x: rect.midX, y: rect.midY).coordinate
                    prepareViewport(center: .init(latitude: center.latitude, longitude: NativeMapProjection.delta(center.longitude, period: 360)),
                        radius: max(1000, hypot(rect.width, rect.height) * MKMetersPerMapPointAtLatitude(center.latitude) * 2))
                    map.setVisibleMapRect(rect, edgePadding: .init(top: 60, left: 35, bottom: 70, right: 70), animated: false)
                }
                else {
                    // Apply the empty-library viewport after MapKit's map
                    // configuration, which can reset a region set in makeUIView.
                    setRegion(.init(center: .init(latitude: 36.5, longitude: 137.2), span: .init(latitudeDelta: 16, longitudeDelta: 16)), map: map, animated: false)
                }
            }
            if focusedRevision != next.focusRevision {
                focusedRevision = next.focusRevision
                if let focusPin { map.removeAnnotation(focusPin) }
                focusPin = nil
                if let focus = next.focus {
                    let pin = MKPointAnnotation(); pin.coordinate = focus.coordinate; pin.title = focus.name; focusPin = pin; map.addAnnotation(pin)
                    setRegion(.init(center: focus.coordinate, latitudinalMeters: 800, longitudinalMeters: 800), map: map, animated: !UIAccessibility.isReduceMotionEnabled)
                }
            } else if next.focus == nil, let focusPin { map.removeAnnotation(focusPin); self.focusPin = nil }
            if locatedRevision != next.locateRevision { locatedRevision = next.locateRevision; waitingForFix = true }
            if waitingForFix, let point = next.current { waitingForFix = false; locate(point, map: map, animated: !UIAccessibility.isReduceMotionEnabled) }
            if zoomedRevision != next.zoomRevision {
                zoomedRevision = next.zoomRevision
                pendingZoom *= next.zoomIn ? 0.5 : 2
                animateCamera = !UIAccessibility.isReduceMotionEnabled
            }
            if pitched != next.pitched {
                if pitched != nil { animateCamera = !UIAccessibility.isReduceMotionEnabled }
                pitched = next.pitched
                pendingPitch = true
            }
            scheduleCameraChanges(map)
        }
        private func prepareViewport(center: CLLocationCoordinate2D, radius: CLLocationDistance) {
            committingCamera = nil
            awaitingViewport = true; pendingPitch = true; viewportCenter = center; viewportRadius = radius
        }
        private func setRegion(_ region: MKCoordinateRegion, map: MKMapView, animated: Bool) {
            let fitted = map.regionThatFits(region)
            let alreadyCommitted = !awaitingViewport && Self.regionIsCommitted(fitted, map: map)
            let corner = CLLocationCoordinate2D(latitude: min(85, max(-85, region.center.latitude + region.span.latitudeDelta / 2)), longitude: region.center.longitude)
            prepareViewport(center: region.center, radius: max(1000, MKMapPoint(region.center).distance(to: MKMapPoint(corner)) * 4))
            // MapKit can omit regionDidChange when the fitted region is already
            // visible. Acknowledge only a matching committed region and camera;
            // an outstanding fit or a stale camera must still await its callback.
            if alreadyCommitted { awaitingViewport = false; return }
            map.setRegion(region, animated: animated)
        }
        private static func regionIsCommitted(_ fitted: MKCoordinateRegion, map: MKMapView) -> Bool {
            func sameCenter(_ coordinate: CLLocationCoordinate2D) -> Bool {
                CLLocationCoordinate2DIsValid(coordinate)
                    && abs(coordinate.latitude - fitted.center.latitude) < 0.0000001
                    && abs(NativeMapProjection.delta(coordinate.longitude - fitted.center.longitude, period: 360)) < 0.0000001
            }
            func sameSpan(_ actual: Double, _ expected: Double) -> Bool {
                actual > 0 && expected > 0 && abs(actual - expected) <= max(0.000000001, expected * 0.000001)
            }
            let camera = map.camera, visible = map.region
            return sameCenter(visible.center) && sameCenter(camera.centerCoordinate)
                && camera.centerCoordinateDistance.isFinite && camera.centerCoordinateDistance > 0
                && sameSpan(visible.span.latitudeDelta, fitted.span.latitudeDelta)
                && sameSpan(visible.span.longitudeDelta, fitted.span.longitudeDelta)
        }
        private func locate(_ point: NativePoint, map: MKMapView, animated: Bool) { setRegion(.init(center: .init(latitude: point.lat, longitude: point.lon), latitudinalMeters: 1000, longitudinalMeters: 1000), map: map, animated: animated) }
        private func scheduleCameraChanges(_ map: MKMapView) {
            guard cameraWork == nil else { return }
            let work = DispatchWorkItem { [weak self, weak map] in
                guard let self, let map, self.map === map else { return }
                self.cameraWork = nil
                if self.committingCamera != nil { self.acknowledgeCameraIfCommitted(map) }
                // Region fitting and camera properties do not commit together.
                // Never copy a pre-region camera, including initial 3D, focus
                // and a zoom requested in the same SwiftUI update as a new fit.
                guard !self.awaitingViewport else { return }
                guard self.pendingPitch || self.pendingZoom != 1 || self.viewportCenter != nil else { return }
                let camera = map.camera.copy() as! MKMapCamera
                guard CLLocationCoordinate2DIsValid(camera.centerCoordinate),
                      camera.centerCoordinateDistance.isFinite, camera.centerCoordinateDistance > 0 else { return }
                if let center = self.viewportCenter {
                    guard MKMapPoint(camera.centerCoordinate).distance(to: MKMapPoint(center)) <= self.viewportRadius else { return }
                }
                let pitch: CGFloat = self.parent.pitched ? 55 : 0
                let needsChange = (self.pendingPitch && abs(camera.pitch - pitch) > 0.1) || self.pendingZoom != 1
                self.pendingPitch = false
                self.viewportCenter = nil
                let animated = self.animateCamera; self.animateCamera = false
                guard needsChange else { return }
                let oldDistance = camera.centerCoordinateDistance, oldPitch = camera.pitch
                // Specify the whole pose together. Sequential pitch, center and
                // distance setters can recalculate the preceding camera geometry.
                let target = MKMapCamera(lookingAtCenter: camera.centerCoordinate,
                    fromDistance: min(30_000_000, max(100, oldDistance * self.pendingZoom)),
                    pitch: pitch, heading: camera.heading)
                self.pendingZoom = 1
                guard abs(target.pitch - oldPitch) > 0.1 || abs(target.centerCoordinateDistance - oldDistance) > 0.01 else { return }
                self.committingCamera = target
                self.awaitingViewport = true
                map.setCamera(target, animated: animated)
                self.scheduleCameraChanges(map)
            }
            cameraWork = work
            DispatchQueue.main.async(execute: work)
        }
        private func acknowledgeCameraIfCommitted(_ map: MKMapView) {
            guard let target = committingCamera else { return }
            let actual = map.camera
            let centerMatches = abs(actual.centerCoordinate.latitude - target.centerCoordinate.latitude) < 0.00001
                && abs(NativeMapProjection.delta(actual.centerCoordinate.longitude - target.centerCoordinate.longitude, period: 360)) < 0.00001
            // MapKit may limit pitch at a large viewing distance. A committed
            // center, distance and heading must release the production queue;
            // the street-scale selftest separately waits for the actual 55° pose.
            guard centerMatches,
                  abs(actual.centerCoordinateDistance - target.centerCoordinateDistance) <= max(1, target.centerCoordinateDistance * 0.01),
                  abs(NativeMapProjection.delta(actual.heading - target.heading, period: 360)) < 0.5 else { return }
            committingCamera = nil
            awaitingViewport = false
        }
        func cancelCameraChanges() { cameraWork?.cancel(); cameraWork = nil }
        #if DEBUG
        var cameraChangesSettled: Bool { !awaitingViewport && committingCamera == nil && !pendingPitch && cameraWork == nil && viewportCenter == nil && pendingZoom == 1 }
        #endif
        private static func fitRect(_ walks: [NativeWalk]) -> MKMapRect? {
            let points = walks.flatMap(\.points).filter { $0.lat.isFinite && $0.lon.isFinite && abs($0.lat) <= 85 && abs($0.lon) <= 180 }
                .map { MKMapPoint(CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)) }
            guard let arc = NativeMapProjection.minimumArc(points.map(\.x), period: MKMapRect.world.width),
                  let lowerY = points.map(\.y).min(), let upperY = points.map(\.y).max() else { return nil }
            // Fit the local world copy across ±180°, rather than the empty
            // nearly-worldwide gap between the same saved coordinates.
            return MKMapRect(x: arc.lowerBound, y: lowerY, width: max(1, arc.width), height: max(1, upperY - lowerY))
        }
        private static func lines(_ points: [NativePoint], active: Bool) -> [MKPolyline] {
            var output: [MKPolyline] = []; var segment: [MKMapPoint] = []
            func flush() { if segment.count > 1 { let line = NativeAnswerPolyline(points: segment, count: segment.count); line.active = active; output.append(line) }; segment = [] }
            for p in points {
                guard p.lat.isFinite, p.lon.isFinite, abs(p.lat) <= 85, abs(p.lon) <= 180 else { flush(); continue }
                if p.isBreak { flush() }
                var projected = MKMapPoint(CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon))
                if let previous = segment.last { projected.x = NativeMapProjection.nearest(projected.x, to: previous.x, period: MKMapRect.world.width) }
                segment.append(projected)
            }
            flush(); return output
        }
        @objc func pick(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let map else { return }
            let coordinate = map.convert(gesture.location(in: map), toCoordinateFrom: map)
            guard CLLocationCoordinate2DIsValid(coordinate), abs(coordinate.latitude) <= 85 else { return }
            parent.onPick(.init(name: "選んだ場所", lat: coordinate.latitude, lon: coordinate.longitude))
        }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if committingCamera != nil { acknowledgeCameraIfCommitted(mapView) }
            else { awaitingViewport = false }
            scheduleCameraChanges(mapView)
            // MapKit can call back synchronously from updateUIView; publish camera
            // changes on the next turn to avoid mutating SwiftUI state mid-render.
            let region = mapView.region
            DispatchQueue.main.async { [weak self, weak mapView] in
                guard let self, let mapView, self.map === mapView else { return }
                self.parent.onRegion(region)
            }
        }
        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            if committingCamera != nil { scheduleCameraChanges(mapView) }
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? NativeAnswerPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line); renderer.strokeColor = line.active ? .systemBlue : UIColor.label.withAlphaComponent(0.7); renderer.lineWidth = line.active ? 3 : 2; renderer.lineJoin = .round; renderer.lineCap = .round; return renderer
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "destination", for: annotation) as! MKMarkerAnnotationView
            view.canShowCallout = true; view.glyphImage = UIImage(systemName: "flag.fill"); view.markerTintColor = .label
            return view
        }
    }
}
private final class NativeAnswerPolyline: MKPolyline { var active = false }
private final class NativeAnswerFlagAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D; let title: String?
    init(_ flag: NativeFlag) { coordinate = .init(latitude: flag.point.lat, longitude: flag.point.lon); title = flag.name; super.init() }
}


#if DEBUG
@MainActor fileprivate extension NativeAnswerMapView {
    init(captureKey:String,model:NativeAppModel) {
        self._model=ObservedObject(wrappedValue:model)
        self._captureMode=State(initialValue:captureKey)
        self._satellite=State(initialValue:captureKey == "answerSatellite")
        self._pitched=State(initialValue:captureKey == "answer3D")
        if captureKey == "answerSearch" {
            self._query=State(initialValue:"東京駅")
            self._showingSearch=State(initialValue:true)
        }
        if captureKey == "answerSelection",let place=Self.capturePlace(model) {
            self._selected=State(initialValue:place)
            self._focusRevision=State(initialValue:1)
        }
    }
    static func capturePlace(_ model:NativeAppModel)->NativeAnswerPlace? {
        guard let raw=(model.library["bookmarks"] as? [[String:Any]])?.first,
              let point=NativePoint(json:raw) else {return nil}
        return NativeAnswerPlace(name:"検証用："+(raw["name"] as? String ?? "保存した場所"),lat:point.lat,lon:point.lon)
    }
}

/// Instantiates the ordinary answer map with test-only initial state. Search
/// rows use a labeled saved fixture rather than impersonating an MKLocalSearch response.
@MainActor @ViewBuilder func nativeCaptureAnswerScreen(_ key:String,model:NativeAppModel)->some View {
    if ProcessInfo.processInfo.arguments.contains("-PlainWalkScreenshotFixture"),
       ["answerSearch","answerSelection","answerSatellite","answer3D"].contains(key) {
        if key == "answerSelection",NativeAnswerMapView.capturePlace(model) == nil {
            ContentUnavailableView("検証用のしおりがありません",systemImage:"exclamationmark.triangle")
        } else {
            NativeAnswerMapView(captureKey:key,model:model)
        }
    } else {
        ContentUnavailableView("未対応の地図撮影キー",systemImage:"exclamationmark.triangle",description:Text(key))
    }
}
#endif
