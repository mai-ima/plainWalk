import SwiftUI
import MapKit

/// A local draft keeps point extensions intact; only an explicit Save touches the library.
struct NativeTrackEditDraft {
    private(set) var rawPoints: [[String: Any]]
    private(set) var points: [NativePoint]
    private(set) var revision = 0
    private(set) var distance: Double
    private var history: [Undo] = []
    private enum Undo {
        case replace(Int, [String: Any])
        case insert(Int, [String: Any], [String: Any]?)
    }
    init(points: [[String: Any]]) throws {
        let decoded = points.compactMap(NativePoint.init(json:))
        guard decoded.count == points.count, (2...300_000).contains(decoded.count), points.allSatisfy({ nativeTime($0["t"]) != nil }) else {
            throw NativeError.message("修正には有効な記録点が 2 点以上必要です。")
        }
        rawPoints = points; self.points = decoded; distance = NativeTrackMath.trailDistance(decoded)
    }
    var canUndo: Bool { !history.isEmpty }
    // Revision remains nonzero after undoing every edit, so dirty state compares the draft at Save/Cancel.
    private mutating func remember(_ value: Undo) {
        history.append(value)
        if history.count > 40 { history.removeFirst() }
    }
    private func checkEdge(_ a: NativePoint, _ b: NativePoint) throws {
        guard b.isBreak || NativeTrackMath.distance(a, b) <= 50_000 else {
            throw NativeError.message("記録点の間が 50 km を超えます。先に軌跡を区切ってください。")
        }
    }
    private func checkIndex(_ index: Int) throws {
        guard points.indices.contains(index) else { throw NativeError.message("記録点が見つかりません。") }
    }
    private static func gap(_ value: Bool, in raw: inout [String: Any]) {
        raw["break"] = value
        if raw["gap"] != nil { raw["gap"] = value }
    }
    mutating func move(_ index: Int, latitude: Double, longitude: Double) throws {
        try checkIndex(index)
        guard latitude.isFinite, longitude.isFinite, abs(latitude) <= 85, abs(longitude) <= 180 else {
            throw NativeError.message("この位置には記録点を移動できません。")
        }
        guard points[index].lat != latitude || points[index].lon != longitude else { return }
        var next = points[index]; next.lat = latitude; next.lon = longitude
        if index > 0 { try checkEdge(points[index - 1], next) }
        if index + 1 < points.count { try checkEdge(next, points[index + 1]) }
        remember(.replace(index, rawPoints[index]))
        rawPoints[index]["lat"] = latitude; rawPoints[index]["lon"] = longitude
        rawPoints[index]["edited"] = true; points[index] = next; revision += 1
        distance = NativeTrackMath.trailDistance(points)
    }
    mutating func toggleGap(_ index: Int) throws {
        try checkIndex(index)
        guard index > 0 else { throw NativeError.message("最初の点の前には線がありません。") }
        var next = points[index]; next.isBreak.toggle()
        try checkEdge(points[index - 1], next)
        remember(.replace(index, rawPoints[index]))
        Self.gap(next.isBreak, in: &rawPoints[index]); rawPoints[index]["edited"] = true
        points[index] = next; revision += 1
        distance = NativeTrackMath.trailDistance(points)
    }
    mutating func delete(_ index: Int) throws {
        try checkIndex(index)
        guard points.count > 2 else { throw NativeError.message("記録点は 2 点以上残してください。") }
        let successor = index + 1 < points.count ? rawPoints[index + 1] : nil
        if index > 0, index + 1 < points.count {
            var next = points[index + 1]
            next.isBreak = next.isBreak || points[index].isBreak
            try checkEdge(points[index - 1], next)
        }
        remember(.insert(index, rawPoints[index], successor))
        let carriesGap = points[index].isBreak
        rawPoints.remove(at: index); points.remove(at: index)
        if carriesGap, index < points.count {
            Self.gap(true, in: &rawPoints[index]); rawPoints[index]["edited"] = true
            points[index].isBreak = true
        }
        revision += 1
        distance = NativeTrackMath.trailDistance(points)
    }
    mutating func undo() {
        guard let value = history.popLast() else { return }
        switch value {
        case .replace(let index, let raw):
            rawPoints[index] = raw; points[index] = NativePoint(json: raw)!
        case .insert(let index, let raw, let successor):
            rawPoints.insert(raw, at: index); points.insert(NativePoint(json: raw)!, at: index)
            if let successor { rawPoints[index + 1] = successor; points[index + 1] = NativePoint(json: successor)! }
        }
        revision += 1
        distance = NativeTrackMath.trailDistance(points)
    }
    func matches(_ original: [[String: Any]]) -> Bool {
        (rawPoints as NSArray).isEqual(to: original)
    }

    #if DEBUG
    static func selfTest() throws -> Bool {
        func require(_ condition: @autoclosure () -> Bool, _ label: String) throws {
            guard condition() else { throw NativeError.message("軌跡修正の検証に失敗: " + label) }
        }
        var a = NativePoint(lat: 35, lon: 139, t: 0).json
        a["vendor"] = ["keep": true]
        var b = NativePoint(lat: 35.001, lon: 139, t: 1_000, isBreak: true).json
        b["gap"] = true; b["leg"] = 7
        let c = NativePoint(lat: 35.002, lon: 139, t: 2_000).json
        let original = [a, b, c]
        var draft = try Self(points: original)
        try draft.move(0, latitude: 35.0001, longitude: 139)
        try require(draft.rawPoints[0]["edited"] as? Bool == true, "edited flag")
        try require((draft.rawPoints[0]["vendor"] as? [String: Bool])?["keep"] == true, "unknown metadata")
        try require(nativeTime(draft.rawPoints[0]["t"]) == 0, "timestamp zero")
        draft.undo(); try require(draft.matches(original), "move undo")
        try draft.delete(1)
        try require(draft.points.count == 2 && draft.points[1].isBreak, "delete preserves gap")
        try require(NativeTrackMath.trailDistance(draft.points) == 0, "no gap bridge")
        draft.undo(); try require(draft.matches(original), "delete undo includes successor")
        try draft.toggleGap(1)
        try require(!draft.points[1].isBreak && draft.rawPoints[1]["gap"] as? Bool == false, "gap aliases")
        try require(nativeNumber(draft.rawPoints[1]["leg"]) == 7, "leg metadata")
        draft.undo(); try require(draft.matches(original), "gap undo")
        let before = draft.rawPoints
        // Point 0 is disconnected from point 1, so moving that isolated point
        // is valid. Point 2 remains connected to point 1 and must reject a jump.
        try draft.move(0, latitude: -35, longitude: -139)
        try require(draft.points[0].lat == -35 && draft.points[1].isBreak, "isolated point respects gap")
        draft.undo(); try require(draft.matches(before), "isolated point undo")
        var rejected = false
        do { try draft.move(2, latitude: -35, longitude: -139) } catch { rejected = true }
        try require(rejected && draft.matches(before) && !draft.canUndo, "connected jump rejection is transactional")
        rejected = false
        do { try draft.move(0, latitude: 86, longitude: 139) } catch { rejected = true }
        try require(rejected && draft.matches(before) && !draft.canUndo, "latitude bounds rejection is transactional")
        var two = try Self(points: [a, c])
        rejected = false
        do { try two.delete(0) } catch { rejected = true }
        try require(rejected && two.points.count == 2 && !two.canUndo, "two-point minimum")
        var far = NativePoint(lat: 36, lon: 140, t: 3_000, isBreak: true).json
        far["extra"] = "far"
        var detached = try Self(points: [a, far])
        rejected = false
        do { try detached.toggleGap(1) } catch { rejected = true }
        try require(rejected && detached.points[1].isBreak && !detached.canUndo, "rejected join keeps gap and undo")
        try draft.move(0, latitude: 35.0001, longitude: 139)
        try draft.delete(1)
        try draft.move(1, latitude: 35.0021, longitude: 139)
        draft.undo(); draft.undo(); draft.undo()
        try require(draft.matches(original), "stacked undo indices and metadata")
        var many = try Self(points: original)
        for index in 1...50 { try many.move(0, latitude: 35 + Double(index) * 0.000001, longitude: 139) }
        for _ in 0..<40 { many.undo() }
        try require(!many.canUndo && abs(many.points[0].lat - 35.00001) < 0.00000001, "bounded inverse history")
        return true
    }
    #endif
}

@MainActor struct NativeTrackEditorView: View {
    @ObservedObject var model: NativeAppModel
    let walkID: String
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NativeTrackEditDraft?
    @State private var original: [[String: Any]] = []
    @State private var selected: Int?
    @State private var failure: String?
    @State private var confirmingCancel = false
    @State private var confirmingDelete = false
    @State private var focusRevision = 0
    @State private var fitRevision = 0
    @State private var dirty = false

    private var busyRecording: Bool { model.isRecording || model.isPaused }
    var body: some View {
        NavigationStack {
            Group {
                if let draft {
                    NativeTrackEditMap(points: draft.points, revision: draft.revision, selected: selected,
                        focusRevision: focusRevision, fitRevision: fitRevision,
                        onSelect: { selected = $0; model.haptic() },
                        onMove: { index, coordinate in edit { try $0.move(index, latitude: coordinate.latitude, longitude: coordinate.longitude) } })
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .top) { instructions.padding(12) }
                    .safeAreaInset(edge: .bottom, spacing: 0) { editorPanel(draft) }
                } else {
                    ContentUnavailableView("軌跡を開けません", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                        description: Text(failure ?? "記録点が 2 点以上あるさんぽを選んでください。"))
                }
            }
            .navigationTitle("軌跡を手で修正").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { cancel() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.fontWeight(.semibold).disabled(!dirty || busyRecording) }
            }
        }
        .interactiveDismissDisabled(dirty)
        .task { load() }
        .alert("軌跡の修正", isPresented: Binding(get: { failure != nil && draft != nil }, set: { if !$0 { failure = nil } })) {
            Button("わかりました", role: .cancel) { failure = nil }
        } message: { Text(failure ?? "") }
        .confirmationDialog("修正を保存せずに戻りますか？", isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button("修正を破棄", role: .destructive) { dismiss() }
            Button("修正を続ける", role: .cancel) {}
        }
        .confirmationDialog("この記録点を削除しますか？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("この点を削除", role: .destructive) {
                guard let selected else { return }
                edit { try $0.delete(selected) }
                if let count = draft?.points.count { self.selected = min(selected, count - 1) }
            }
            Button("キャンセル", role: .cancel) {}
        } message: { Text("区切りの点を削除しても、切れていた軌跡はつながりません。直前の 40 回の修正を元に戻せます。") }
    }
    private var instructions: some View {
        Text("線の近くをタップして点を選択。選んだ点を長押ししてドラッグすると、位置を修正できます。")
            .font(.footnote).foregroundStyle(.primary).padding(12).frame(maxWidth: 520)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .allowsHitTesting(false)
    }
    private func editorPanel(_ draft: NativeTrackEditDraft) -> some View {
        VStack(spacing: 10) {
            HStack {
                Label("\(model.distanceText(draft.distance)) \(model.distanceUnit)", systemImage: "shoeprints.fill")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                Spacer()
                Button { self.draft?.undo(); dirty = self.draft.map { !$0.matches(original) } ?? false; if let selected { self.selected = min(selected, (self.draft?.points.count ?? 1) - 1) } } label: { Label("元に戻す", systemImage: "arrow.uturn.backward") }
                    .disabled(!draft.canUndo).font(.subheadline)
                Button { fitRevision += 1 } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44) }.accessibilityLabel("軌跡全体を表示")
            }
            if let selected, draft.points.indices.contains(selected) {
                HStack {
                    Button { select(max(0, selected - 1)) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.disabled(selected == 0).accessibilityLabel("前の記録点")
                    Spacer()
                    VStack(spacing: 3) {
                        Text("\(selected + 1) / \(draft.points.count) 点目").font(.subheadline.weight(.semibold)).monospacedDigit()
                        Text(NativeRecordDates.time(NativeRecordDates.date(draft.points[selected].t))).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { select(min(draft.points.count - 1, selected + 1)) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(selected + 1 == draft.points.count).accessibilityLabel("次の記録点")
                }
                HStack(spacing: 12) {
                    Button { edit { try $0.toggleGap(selected) } } label: {
                        Label(draft.points[selected].isBreak ? "前の点とつなぐ" : "ここで区切る", systemImage: draft.points[selected].isBreak ? "link" : "scissors")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }.buttonStyle(.bordered).disabled(selected == 0)
                    Button(role: .destructive) { confirmingDelete = true } label: { Image(systemName: "trash").frame(width: 36, height: 36) }
                        .buttonStyle(.bordered).disabled(draft.points.count <= 2).accessibilityLabel("この記録点を削除")
                }
            } else {
                Button { select(0) } label: { Text("最初の記録点を選ぶ").frame(maxWidth: .infinity, minHeight: 40) }.buttonStyle(.bordered)
            }
        }.padding(.horizontal, 16).padding(.bottom, 12).padding(.top, 6).background(.regularMaterial)
    }
    private func select(_ index: Int) { selected = index; focusRevision += 1; model.haptic() }
    private func load() {
        guard draft == nil else { return }
        guard !busyRecording else { failure = "記録を終了してから軌跡を修正してください。"; return }
        guard let walk = model.walks.first(where: { $0.id == walkID }), let raw = walk.raw["points"] as? [[String: Any]] else {
            failure = "さんぽが見つかりません。"; return
        }
        do { original = raw; draft = try NativeTrackEditDraft(points: raw) }
        catch { failure = error.localizedDescription }
    }
    private func edit(_ change: (inout NativeTrackEditDraft) throws -> Void) {
        guard !busyRecording else { failure = "記録を終了してから軌跡を修正してください。"; return }
        do { if var value = draft { try change(&value); draft = value; dirty = !value.matches(original); model.haptic() } }
        catch { failure = error.localizedDescription }
    }
    private func cancel() { if dirty { confirmingCancel = true } else { dismiss() } }
    private func save() {
        guard let draft, dirty else { return }
        guard !busyRecording else { failure = "記録を終了してから軌跡を修正してください。"; return }
        do {
            let walks = model.library["walks"] as? [[String: Any]] ?? []
            guard let current = walks.first(where: { $0["id"] as? String == walkID }),
                  let currentPoints = current["points"] as? [[String: Any]] else { throw NativeError.message("さんぽが削除されています。修正を保存できません。") }
            guard (currentPoints as NSArray).isEqual(to: original) else {
                throw NativeError.message("編集中に元の軌跡が変更されました。一度戻り、最新のさんぽを開いてください。")
            }
            try model.updateLibrary { library in
                var values = library["walks"] as? [[String: Any]] ?? []
                if let index = values.firstIndex(where: { $0["id"] as? String == walkID }) {
                    values[index]["points"] = draft.rawPoints
                    if values[index]["distance"] != nil { values[index]["distance"] = NativeTrackMath.trailDistance(draft.points) }
                }
                library["walks"] = values
            }
            model.haptic(); dismiss()
        } catch { failure = error.localizedDescription }
    }
}

/// One path overlay and one draggable annotation keep large imports out of the annotation layer.
private struct NativeTrackEditMap: UIViewRepresentable {
    let points: [NativePoint]
    let revision: Int
    let selected: Int?
    let focusRevision: Int
    let fitRevision: Int
    let onSelect: (Int?) -> Void
    let onMove: (Int, CLLocationCoordinate2D) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
        map.isRotateEnabled = false; map.isPitchEnabled = false; map.showsScale = true
        map.delegate = context.coordinator; context.coordinator.map = map
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pick(_:)))
        tap.delegate = context.coordinator; map.addGestureRecognizer(tap)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) { context.coordinator.update(self, map: map) }
    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) { map.delegate = nil; coordinator.map = nil }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: NativeTrackEditMap
        weak var map: MKMapView?
        private var lastRevision = -1
        private var lastFit = -1
        private var lastFocus = -1
        private var overlay: NativeTrackEditOverlay?
        private var pin: NativeTrackEditPin?
        init(_ parent: NativeTrackEditMap) { self.parent = parent }
        func update(_ next: NativeTrackEditMap, map: MKMapView) {
            parent = next
            if lastRevision != next.revision {
                lastRevision = next.revision
                if let overlay { map.removeOverlay(overlay) }
                let line = NativeTrackEditOverlay(points: next.points); overlay = line; map.addOverlay(line)
            }
            if lastFit != next.fitRevision {
                lastFit = next.fitRevision
                if let overlay {
                    var rect = overlay.boundingMapRect
                    let minimum = 180 * MKMapPointsPerMeterAtLatitude(overlay.coordinate.latitude)
                    if rect.width < minimum { rect = rect.insetBy(dx: -(minimum - rect.width) / 2, dy: 0) }
                    if rect.height < minimum { rect = rect.insetBy(dx: 0, dy: -(minimum - rect.height) / 2) }
                    map.setVisibleMapRect(rect, edgePadding: .init(top: 100, left: 35, bottom: 40, right: 35), animated: lastFit > 0 && !UIAccessibility.isReduceMotionEnabled)
                }
            }
            if let index = next.selected, next.points.indices.contains(index) {
                let point = next.points[index]
                let coordinate = CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
                if pin?.index != index {
                    if let pin { map.removeAnnotation(pin) }
                    let annotation = NativeTrackEditPin(index: index, coordinate: coordinate)
                    pin = annotation; map.addAnnotation(annotation)
                    map.selectAnnotation(annotation, animated: false)
                } else if let pin, map.view(for: pin)?.dragState != .dragging { pin.coordinate = coordinate }
                if lastFocus != next.focusRevision {
                    lastFocus = next.focusRevision
                    if next.focusRevision > 0 { map.setCenter(coordinate, animated: !UIAccessibility.isReduceMotionEnabled) }
                }
            } else if let pin { map.removeAnnotation(pin); self.pin = nil }
        }
        @objc func pick(_ tap: UITapGestureRecognizer) {
            guard let map else { return }
            let coordinate = map.convert(tap.location(in: map), toCoordinateFrom: map)
            let target = MKMapPoint(coordinate)
            let scale = map.visibleMapRect.width / max(1, Double(map.bounds.width))
            var nearest: Int?; var best = pow(scale * 30, 2)
            let world = MKMapRect.world.width
            for (index, point) in parent.points.enumerated() {
                let p = MKMapPoint(CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon))
                let x = abs(p.x - target.x); let dx = min(x, world - x); let dy = p.y - target.y
                let distance = dx * dx + dy * dy
                if distance < best { nearest = index; best = distance }
            }
            parent.onSelect(nearest)
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view { if current is MKAnnotationView { return false }; view = current.superview }
            return true
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? NativeTrackEditOverlay else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = NativeTrackEditRenderer(overlay: line)
            renderer.strokeColor = .label; renderer.lineWidth = 3; renderer.lineCap = .round; renderer.lineJoin = .round
            return renderer
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is NativeTrackEditPin else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "editPoint") as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "editPoint")
            view.annotation = annotation; view.isDraggable = true; view.canShowCallout = false
            view.markerTintColor = .systemBlue; view.glyphImage = UIImage(systemName: "hand.point.up.left.fill")
            view.displayPriority = .required
            view.accessibilityLabel = "選択した記録点。長押しして位置を動かす"
            return view
        }
        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            guard let pin = view.annotation as? NativeTrackEditPin else { return }
            if newState == .ending {
                parent.onMove(pin.index, pin.coordinate); view.dragState = .none
                // Rejected edits restore the pin immediately, including when SwiftUI state did not change.
                if parent.points.indices.contains(pin.index) {
                    let p = parent.points[pin.index]; pin.coordinate = .init(latitude: p.lat, longitude: p.lon)
                }
            } else if newState == .canceling {
                if parent.points.indices.contains(pin.index) {
                    let p = parent.points[pin.index]; pin.coordinate = .init(latitude: p.lat, longitude: p.lon)
                }
                view.dragState = .none
            }
        }
    }
}

private final class NativeTrackEditPin: MKPointAnnotation {
    let index: Int
    init(index: Int, coordinate: CLLocationCoordinate2D) { self.index = index; super.init(); self.coordinate = coordinate }
}
private final class NativeTrackEditOverlay: NSObject, MKOverlay {
    let points: [NativePoint]
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    init(points: [NativePoint]) {
        self.points = points
        var rect = MKMapRect.null
        for point in points {
            let p = MKMapPoint(CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon))
            rect = rect.union(.init(x: p.x, y: p.y, width: 0.001, height: 0.001))
        }
        boundingMapRect = rect
        coordinate = MKMapPoint(x: rect.midX, y: rect.midY).coordinate
        super.init()
    }
}
private final class NativeTrackEditRenderer: MKOverlayPathRenderer {
    override func createPath() {
        guard let line = overlay as? NativeTrackEditOverlay else { return }
        let path = CGMutablePath()
        let stride = max(1, line.points.count / 8_000)
        for (index, value) in line.points.enumerated() {
            let starts = index == 0 || value.isBreak
            let ends = index + 1 == line.points.count || line.points[index + 1].isBreak
            guard starts || ends || index % stride == 0 else { continue }
            let point = point(for: MKMapPoint(CLLocationCoordinate2D(latitude: value.lat, longitude: value.lon)))
            if starts { path.move(to: point) } else { path.addLine(to: point) }
        }
        self.path = path
    }
}
