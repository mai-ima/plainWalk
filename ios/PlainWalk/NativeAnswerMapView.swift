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
    @State private var searchError: String?
    @State private var activeSearch: MKLocalSearch?
    @State private var searchRegion = MKCoordinateRegion(center: .init(latitude: 36.5, longitude: 137.2), span: .init(latitudeDelta: 16, longitudeDelta: 16))
    @State private var focusRevision = 0
    @State private var locateRevision = 0
    @State private var zoomRevision = 0
    @State private var zoomIn = true

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                NativeAnswerMapSurface(walks: model.walks, activePoints: model.activePoints, libraryRevision: model.libraryRevision,
                    flags: model.flags, current: model.currentPoint, satellite: satellite, pitched: pitched,
                    focus: selected, focusRevision: focusRevision, locateRevision: locateRevision,
                    zoomRevision: zoomRevision, zoomIn: zoomIn,
                    onRegion: { searchRegion = $0 }, onPick: select)
                    .ignoresSafeArea(edges: .bottom)
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchResults
                }
                VStack { Spacer(); HStack { Spacer(); controls } }.padding(16)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let selected { selectionCard(selected) }
            }
            .navigationTitle("答え合わせマップ").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { model.closeSheet() }.fontWeight(.semibold) } }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "場所や住所を検索")
            .task(id: query) { await search() }
            .onDisappear { activeSearch?.cancel(); activeSearch = nil }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
    }

    private var controls: some View {
        VStack(spacing: 10) {
            mapButton(satellite ? "標準地図に切り替える" : "衛星写真に切り替える", symbol: satellite ? "map" : "globe.asia.australia.fill") { satellite.toggle() }
            Button { model.haptic(); pitched.toggle() } label: { Text(pitched ? "2D" : "3D").font(.system(size: 15, weight: .semibold)).frame(width: 44, height: 44).background(.regularMaterial, in: Circle()) }
                .buttonStyle(.plain).accessibilityLabel(pitched ? "平面表示に切り替える" : "立体表示に切り替える")
            mapButton("現在地", symbol: "scope") { model.locate(); locateRevision += 1 }
            VStack(spacing: 0) {
                Button { zoomIn = true; zoomRevision += 1 } label: { Image(systemName: "plus").frame(width: 44, height: 44) }.accessibilityLabel("地図を拡大")
                Divider().frame(width: 25)
                Button { zoomIn = false; zoomRevision += 1 } label: { Image(systemName: "minus").frame(width: 44, height: 44) }.accessibilityLabel("地図を縮小")
            }.font(.system(size: 17, weight: .medium)).background(.regularMaterial, in: Capsule()).buttonStyle(.plain)
        }.foregroundStyle(.primary).shadow(color: .black.opacity(0.08), radius: 10, y: 5)
    }
    private func mapButton(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button { model.haptic(); action() } label: { Image(systemName: symbol).font(.system(size: 21)).frame(width: 44, height: 44).background(.regularMaterial, in: Circle()) }
            .buttonStyle(.plain).accessibilityLabel(label)
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
        }.padding(16).background(.regularMaterial)
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

#if DEBUG
    /// Exercise MapKit's real configuration/region/camera interaction, including
    /// the initial nil-to-flat pitch transition that previously reset the map.
    static func cameraSelfTest() throws -> Bool {
        func require(_ condition: @autoclosure () -> Bool, _ name: String) throws {
            guard condition() else { throw NativeError.message("答え合わせマップのカメラ検証に失敗: " + name) }
        }
        func configuredMap(walks: [NativeWalk] = [], current: NativePoint? = nil) -> MKMapView {
            let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
            let surface = NativeAnswerMapSurface(walks: walks, activePoints: [], libraryRevision: 0,
                flags: [], current: current, satellite: false, pitched: false,
                focus: nil, focusRevision: 0, locateRevision: 0, zoomRevision: 0, zoomIn: true,
                onRegion: { _ in }, onPick: { _ in })
            let coordinator = NativeAnswerMapSurface.Coordinator(surface)
            coordinator.map = map; map.delegate = coordinator
            // Reproduce makeUIView's initial region before the configuration is
            // applied, then exercise the exact update path used by SwiftUI.
            map.setRegion(.init(center: .init(latitude: 36.5, longitude: 137.2), span: .init(latitudeDelta: 16, longitudeDelta: 16)), animated: false)
            coordinator.update(surface, map: map)
            map.layoutIfNeeded()
            coordinator.update(surface, map: map)
            map.delegate = nil; coordinator.map = nil
            return map
        }
        let empty = configuredMap()
        try require((30...45).contains(empty.region.center.latitude) && (125...150).contains(empty.region.center.longitude), "空データで日本を表示")
        try require(empty.region.span.latitudeDelta > 5, "空データで地域全体を表示")
        try require(abs(empty.camera.pitch) < 0.1, "初期表示は平面")

        let point = NativePoint(lat: 35.6812, lon: 139.7671, t: 1_000)
        let located = configuredMap(current: point)
        try require(abs(located.region.center.latitude - point.lat) < 0.01 && abs(located.region.center.longitude - point.lon) < 0.01, "初回の平面設定でGPS中心を保持")
        try require(located.region.span.latitudeDelta < 0.1, "GPSの表示倍率を保持")

        let points = [NativePoint(lat: 34.68, lon: 135.50, t: 1_000), NativePoint(lat: 34.69, lon: 135.52, t: 11_000)]
        guard let walk = NativeWalk(json: ["id": "camera-self-test", "name": "camera", "start": 1_000.0, "end": 11_000.0, "points": points.map(\.json)]) else {
            throw NativeError.message("カメラ検証用の軌跡を生成できません。")
        }
        let routed = configuredMap(walks: [walk])
        try require(points.allSatisfy { routed.visibleMapRect.contains(MKMapPoint(CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon))) }, "初回の平面設定で軌跡全体を保持")
        try require(abs(routed.region.center.latitude - 34.685) < 0.05 && abs(routed.region.center.longitude - 135.51) < 0.05, "軌跡の中心を保持")
        try require(routed.region.span.latitudeDelta < 0.2, "軌跡の表示倍率を保持")
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
        map.showsUserLocation = true; map.showsCompass = true; map.showsBuildings = true; map.isPitchEnabled = true; map.isRotateEnabled = true
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "destination")
        let scale = MKScaleView(mapView: map); scale.scaleVisibility = .adaptive; scale.translatesAutoresizingMaskIntoConstraints = false
        map.addSubview(scale)
        NSLayoutConstraint.activate([scale.leadingAnchor.constraint(equalTo: map.safeAreaLayoutGuide.leadingAnchor, constant: 12), scale.topAnchor.constraint(equalTo: map.safeAreaLayoutGuide.topAnchor, constant: 10)])
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pick(_:))); longPress.minimumPressDuration = 0.65
        map.addGestureRecognizer(longPress)
        map.setRegion(MKCoordinateRegion(center: .init(latitude: 36.5, longitude: 137.2), span: .init(latitudeDelta: 16, longitudeDelta: 16)), animated: false)
        context.coordinator.map = map
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) { context.coordinator.update(self, map: map) }
    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) { map.delegate = nil; coordinator.map = nil }

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
                else if let first = savedLines.first { var rect = first.boundingMapRect; for line in savedLines.dropFirst() { rect = rect.union(line.boundingMapRect) }; map.setVisibleMapRect(rect, edgePadding: .init(top: 60, left: 35, bottom: 70, right: 70), animated: false) }
                else {
                    // Apply the empty-library viewport after MapKit's map
                    // configuration, which can reset a region set in makeUIView.
                    map.setRegion(.init(center: .init(latitude: 36.5, longitude: 137.2), span: .init(latitudeDelta: 16, longitudeDelta: 16)), animated: false)
                }
            }
            if focusedRevision != next.focusRevision {
                focusedRevision = next.focusRevision
                if let focusPin { map.removeAnnotation(focusPin) }
                focusPin = nil
                if let focus = next.focus {
                    let pin = MKPointAnnotation(); pin.coordinate = focus.coordinate; pin.title = focus.name; focusPin = pin; map.addAnnotation(pin)
                    map.setRegion(.init(center: focus.coordinate, latitudinalMeters: 800, longitudinalMeters: 800), animated: !UIAccessibility.isReduceMotionEnabled)
                }
            } else if next.focus == nil, let focusPin { map.removeAnnotation(focusPin); self.focusPin = nil }
            if locatedRevision != next.locateRevision { locatedRevision = next.locateRevision; waitingForFix = true }
            if waitingForFix, let point = next.current { waitingForFix = false; locate(point, map: map, animated: !UIAccessibility.isReduceMotionEnabled) }
            if zoomedRevision != next.zoomRevision {
                zoomedRevision = next.zoomRevision; let camera = map.camera.copy() as! MKMapCamera
                camera.centerCoordinateDistance = min(30_000_000, max(100, camera.centerCoordinateDistance * (next.zoomIn ? 0.5 : 2)))
                map.setCamera(camera, animated: !UIAccessibility.isReduceMotionEnabled)
            }
            if pitched != next.pitched {
                let changesPitch = pitched != nil || next.pitched
                pitched = next.pitched
                // The first flat configuration already has zero pitch. Reading
                // its camera here can return MapKit's pre-region default and
                // overwrite the initial Japan/GPS/trail viewport.
                if changesPitch {
                    let camera = map.camera.copy() as! MKMapCamera; camera.pitch = next.pitched ? 55 : 0
                    map.setCamera(camera, animated: !UIAccessibility.isReduceMotionEnabled)
                }
            }
        }
        private func locate(_ point: NativePoint, map: MKMapView, animated: Bool) { map.setRegion(.init(center: .init(latitude: point.lat, longitude: point.lon), latitudinalMeters: 1000, longitudinalMeters: 1000), animated: animated) }
        private static func lines(_ points: [NativePoint], active: Bool) -> [MKPolyline] {
            var output: [MKPolyline] = []; var segment: [CLLocationCoordinate2D] = []
            func flush() { if segment.count > 1 { let line = NativeAnswerPolyline(coordinates: segment, count: segment.count); line.active = active; output.append(line) }; segment = [] }
            for p in points {
                guard p.lat.isFinite, p.lon.isFinite, abs(p.lat) <= 85, abs(p.lon) <= 180 else { flush(); continue }
                if p.isBreak { flush() }
                segment.append(.init(latitude: p.lat, longitude: p.lon))
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
            // MapKit can call back synchronously from updateUIView; publish camera
            // changes on the next turn to avoid mutating SwiftUI state mid-render.
            let region = mapView.region
            DispatchQueue.main.async { [weak self] in
                guard let self, self.map != nil else { return }
                self.parent.onRegion(region)
            }
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
