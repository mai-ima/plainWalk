import SwiftUI
import UIKit
import ImageIO

// Native map rendering uses projected GPS coordinates. Panning changes only the camera,
// never the stored trail. No Web view or remote page is involved in this screen.
@MainActor struct NativeMyMapView: View {
    @ObservedObject var model: NativeAppModel
    @State private var camera = NativePaperCamera()
    @State private var dragOrigin: NativePaperCamera?
    @State private var pinchOrigin: NativePaperCamera?
    @State private var pinching = false
    @State private var followsLocation = true
    @State private var initialized = false
    @State private var savedTraces: [NativePaperTrace] = []
    @State private var doodleTraces: [NativePaperTrace] = []
    @State private var activeTraces: [NativePaperTrace] = []
    @State private var geometryRevision = 0
    @State private var suppressTapUntil = Date.distantPast
    @State private var recordPressed = false
    @State private var selectedSpot: NativeSpot?
    @State private var selectedFlag: NativeFlag?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasSession: Bool { model.isRecording || model.isPaused || !model.activePoints.isEmpty }
    private var visibleModes: [String: Bool] { model.config["transportVisible"] as? [String: Bool] ?? [:] }
    private var focusedID: String? { model.focusedWalkID }
    private var activeGeometryKey: String { "\(model.activePoints.count):\(model.activePoints.first?.t ?? 0):\(model.activePoints.last?.t ?? 0)" }
    private var currentKey: String {
        guard let p = model.currentPoint else { return "none" }
        return "\(p.lat):\(p.lon):\(p.t)"
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let modes = visibleModes
            let camera = camera
            let ink = model.ink
            let fade = hasSession && model.config["fadeOther"] as? Bool != false
            let thicken = model.config["thicken"] as? Bool != false
            let dashed = model.config["line"] as? String == "dashed"
            let smooth = model.config["smooth"] as? Bool != false
            let grid = model.config["grid"] as? Bool == true
            let selection = focusedID
            ZStack {
                model.paper.ignoresSafeArea()
                NativePaperCanvas(saved: savedTraces, active: activeTraces, doodles: doodleTraces,
                    geometryRevision: geometryRevision, camera: camera, size: size, modes: modes, ink: ink,
                    fade: fade, thicken: thicken, dashed: dashed, smooth: smooth, grid: grid, selection: selection)
                .equatable()
                .contentShape(Rectangle())
                .gesture(panGesture)
                .simultaneousGesture(zoomGesture(size: size))
                .onTapGesture(count: 2) { changeZoom(by: 1) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("白地図")
                .accessibilityHint("ドラッグで移動、二本指で拡大・縮小します。保存した道と記録中の道が描かれます。")
                .accessibilityAction(named: Text("拡大")) { changeZoom(by: 1) }
                .accessibilityAction(named: Text("縮小")) { changeZoom(by: -1) }

                if model.walks.isEmpty && model.activePoints.count < 2 && model.spots.isEmpty {
                    emptyHint(size: size).allowsHitTesting(false)
                }
                pinLayer(size: size)
                locationLayer(size: size).allowsHitTesting(false)

                VStack(spacing: 0) {
                    header
                    Spacer(minLength: 0)
                    if let id = focusedID, model.walks.contains(where: { $0.id == id }) {
                        Text("選んださんぽを表示しています")
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.bottom, 8).allowsHitTesting(false)
                    }
                    bottomControls(size: size)
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 12)
            }
            .clipped()
            .onAppear { initializeCamera(size: size) }
            .onChange(of: currentKey) { _, _ in
                if followsLocation, let point = model.currentPoint { self.camera.center = NativePaperPoint(point) }
            }
            .onChange(of: model.mapFocusRevision) { _, _ in
                followsLocation = false
                if let id = model.focusedWalkID, let walk = model.walks.first(where: { $0.id == id }) {
                    self.camera.fit(walk.points, size: size)
                } else if let point = model.mapFocus {
                    self.camera.center = NativePaperPoint(point); self.camera.zoom = 17
                }
            }
            .task(id: model.libraryRevision) {
                let snapshots = model.walks.map { NativePaperWalkSnapshot(id: $0.id, points: $0.points.map(NativePaperGeoPoint.init)) }
                let rawDoodles = (model.library["doodles"] as? [[String: Any]] ?? []).map { item -> NativePaperWalkSnapshot in
                    let points = item["points"] as? [[String: Any]] ?? []
                    var gap = true
                    let visible = points.compactMap { raw -> NativePaperGeoPoint? in
                        if raw["done"] as? Bool == true { gap = true; return nil }
                        guard let lat = nativeNumber(raw["lat"]), let lon = nativeNumber(raw["lon"]), abs(lat) <= 85, abs(lon) <= 180 else { gap = true; return nil }
                        let point = NativePaperGeoPoint(lat: lat, lon: lon, isBreak: gap || raw["break"] as? Bool == true, mode: "walking")
                        gap = false; return point
                    }
                    return NativePaperWalkSnapshot(id: item["id"] as? String ?? "doodle", points: visible)
                }
                let traces = await NativePaperGeometry.build(snapshots)
                let sketches = await NativePaperGeometry.build(rawDoodles, countVisits: false)
                guard !Task.isCancelled else { return }
                savedTraces = traces
                doodleTraces = sketches
                geometryRevision += 1
            }
            .task(id: activeGeometryKey) {
                // Timer updates do not reproject the entire active recording. The
                // immutable scalar snapshot is processed off the main actor only
                // when a GPS fix is accepted, a session is reset, or restored.
                let points = model.activePoints.map(NativePaperGeoPoint.init)
                let traces = await NativePaperGeometry.activeTraces(points)
                guard !Task.isCancelled else { return }
                activeTraces = traces
                geometryRevision += 1
            }
        }
        .sheet(item: $selectedSpot) { spot in NativeMapSpotPreview(spot: spot) }
        .sheet(item: $selectedFlag) { flag in NativeMapFlagPreview(model: model, flag: flag) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            circleButton("メニュー", symbol: "line.3.horizontal", action: model.openMenu)
            VStack(spacing: 3) {
                Text("歩いた道が、地図になる。")
                Text("まだ誰も描いていない場所を、あなたの一歩で。")
            }
            .font(.system(size: 11, weight: .medium)).lineLimit(1)
            .minimumScaleFactor(0.75).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).foregroundStyle(model.ink.opacity(0.8))
            circleButton("答え合わせマップ", symbol: "map", action: model.openAnswerMap)
        }
    }

    private func bottomControls(size: CGSize) -> some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 13) {
                    metric("今日の歩数", value: stepsText, unit: "歩", symbol: "shoeprints.fill")
                    metric("開拓した道", value: model.distanceText(model.todayPioneered), unit: model.distanceUnit, symbol: "pencil.tip")
                    metric("総開拓距離", value: model.distanceText(model.totalPioneered), unit: model.distanceUnit, symbol: "flag")
                }
                .frame(width: min(166, size.width * 0.44), alignment: .leading)
                .allowsHitTesting(false)
                Spacer(minLength: 0)
                VStack(spacing: 13) {
                    if hasSession {
                        tool("ここいいな", symbol: "camera", action: model.openSpotCapture)
                    }
                    tool("現在地", symbol: "scope") { followsLocation = true; model.locate(); if let point = model.currentPoint { camera.center = NativePaperPoint(point) } }
                    tool("地図レイヤー", symbol: "square.3.layers.3d", action: model.openLayers)
                }
            }
            VStack(spacing: 8) {
                if hasSession {
                    Text("\(model.isPaused ? "一時停止" : "記録中")  \(elapsedText)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(model.paper).padding(.horizontal, 12).padding(.vertical, 7)
                        .background(model.ink, in: Capsule()).monospacedDigit()
                        .accessibilityLabel("\(model.isPaused ? "一時停止" : "記録中")、\(elapsedText)")
                }
                Button {
                    guard Date() >= suppressTapUntil else { return }
                    model.haptic()
                    if hasSession { model.togglePause() } else { model.beginRecording() }
                } label: {
                    Image(systemName: hasSession ? (model.isPaused ? "play.fill" : "pause.fill") : "shoeprints.fill")
                        .font(.system(size: hasSession ? 28 : 32, weight: .regular))
                        .foregroundStyle(hasSession ? model.paper : model.ink)
                        .frame(width: 72, height: 72)
                        .background(hasSession ? model.ink : Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
                        .overlay { Circle().stroke(model.ink.opacity(recordPressed ? 0.22 : 0), lineWidth: 5).padding(-5) }
                        .shadow(color: .black.opacity(0.08), radius: 15, y: 7)
                        .scaleEffect(recordPressed && !reduceMotion ? 0.96 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hasSession ? (model.isPaused ? "記録を再開" : "記録を一時停止") : "軌跡を残す")
                .accessibilityHint(hasSession ? "長押しでさんぽを保存して終了します。" : "位置情報を使ってさんぽを記録します。")
                .accessibilityAction(named: Text("さんぽを保存して終了")) { if hasSession { model.finishRecording() } }
                .onLongPressGesture(minimumDuration: 0.85, pressing: { recordPressed = $0 }) {
                    guard hasSession else { return }
                    suppressTapUntil = Date().addingTimeInterval(1)
                    model.haptic(); model.finishRecording()
                }
                Text(hasSession ? (model.isPaused ? "タップで再開" : "タップで一時停止") : "軌跡を残す")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.bottom, 2)
            .frame(width: 140)
        }
    }

    private var elapsedText: String {
        let value = model.elapsed.isFinite ? Int(min(315_360_000, max(0, model.elapsed))) : 0
        if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60) }
        return String(format: "%d:%02d", value / 60, value % 60)
    }
    private var stepsText: String {
        guard let steps = model.todaySteps, steps.isFinite, steps >= 0 else { return "—" }
        return Int(min(steps, 1_000_000_000)).formatted(.number)
    }
    private func metric(_ label: String, value: String, unit: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 26)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: symbol).font(.system(size: 17, weight: .light)).frame(width: 20)
                Text(value).font(.system(size: 31, weight: .semibold, design: .rounded)).minimumScaleFactor(0.55).lineLimit(1).monospacedDigit().layoutPriority(1)
                Text(unit).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize()
            }
            .foregroundStyle(model.ink)
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(label)、\(value) \(unit)")
    }
    private func circleButton(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button { model.haptic(); action() } label: {
            Image(systemName: symbol).font(.system(size: 21, weight: .regular)).frame(width: 44, height: 44)
                .foregroundStyle(model.ink).background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.07), radius: 14, y: 6)
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
    private func tool(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 5) {
            Button { model.haptic(); action() } label: {
                Image(systemName: symbol).font(.system(size: 24, weight: .regular))
                    .frame(width: 54, height: 54).foregroundStyle(model.ink)
                    .background(.regularMaterial, in: Circle()).shadow(color: .black.opacity(0.07), radius: 13, y: 6)
            }.buttonStyle(.plain).accessibilityLabel(label)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
    private func emptyHint(size: CGSize) -> some View {
        VStack(spacing: 6) {
            NativePaperLineSample(dashed: false).stroke(model.ink.opacity(0.12), style: StrokeStyle(lineWidth: 1.2, lineCap: .round)).frame(width: 32, height: 21)
            Text("「軌跡を残す」をタップして\n最初の道を描こう").font(.system(size: 12)).lineSpacing(3).multilineTextAlignment(.center).foregroundStyle(.secondary.opacity(0.6))
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, min(230, size.height * 0.34))
    }
    @ViewBuilder private func pinLayer(size: CGSize) -> some View {
        ForEach(model.flags) { flag in
            let p = camera.screen(NativePaperPoint(flag.point), size: size)
            if isVisible(p, size: size, margin: 50) {
                Button { selectedFlag = flag; model.haptic() } label: {
                    VStack(spacing: 2) { Image(systemName: "flag.fill").font(.system(size: 24)); Text(flag.name).font(.system(size: 9)).lineLimit(1).frame(maxWidth: 90) }
                        .foregroundStyle(model.ink).padding(7).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).position(x: p.x, y: p.y - 18).accessibilityLabel("目的地、\(flag.name)")
            }
        }
        ForEach(model.spots) { spot in
            let p = camera.screen(NativePaperPoint(spot.point), size: size)
            let allowed = spot.photoData != nil ? model.config["showPhotos"] as? Bool != false : model.config["showTweets"] as? Bool == true
            if allowed && isVisible(p, size: size, margin: 60) {
                Button { selectedSpot = spot; model.haptic() } label: { NativePaperPhotoPin(spot: spot, style: model.config["pin"] as? String ?? "badge", ink: model.ink) }
                    .buttonStyle(.plain).frame(width: 44, height: 52).position(x: p.x, y: p.y - 18)
                    .accessibilityLabel(spot.text.isEmpty ? "ここいいな" : spot.text)
            }
        }
    }
    @ViewBuilder private func locationLayer(size: CGSize) -> some View {
        if let point = model.currentPoint {
            let p = camera.screen(NativePaperPoint(point), size: size)
            if isVisible(p, size: size, margin: 120) {
                if model.config["highlight"] as? Bool != false {
                    let realMPP = camera.metersPerPixel * max(0.1, cos(point.lat * .pi / 180))
                    Circle().fill(Color.blue.opacity(0.13)).frame(width: min(180, max(48, model.accuracy * 2 / realMPP)), height: min(180, max(48, model.accuracy * 2 / realMPP))).position(p)
                }
                if let mark = model.config["locationMark"] as? String, mark != "dot", camera.zoom >= 14 {
                    NativePaperCompanion(kind: mark, walking: !reduceMotion && model.isRecording && point.mode != "vehicle" && Date().timeIntervalSince1970 * 1000 - point.t < 10000)
                        .frame(width: 28, height: 44).rotationEffect(.degrees(heading(for: point)))
                        .position(x: p.x, y: p.y - 15)
                } else {
                    Circle().fill(model.ink).frame(width: 10, height: 10).overlay { Circle().stroke(model.paper, lineWidth: 2) }.position(p)
                }
                if let flag = model.flags.first {
                    let bearing = NativePaperGeometry.bearing(from: point, to: flag.point)
                    VStack(spacing: 3) { Text("\(model.distanceText(NativePaperGeometry.distance(point, flag.point))) \(model.distanceUnit)").font(.system(size: 11, weight: .semibold)); Image(systemName: "location.north.fill").font(.system(size: 16)).rotationEffect(.degrees(bearing)) }
                        .foregroundStyle(model.ink).position(x: min(size.width - 45, max(45, p.x + 32)), y: max(95, p.y - 44))
                }
            }
        }
    }
    private func isVisible(_ p: CGPoint, size: CGSize, margin: CGFloat) -> Bool { p.x >= -margin && p.y >= -margin && p.x <= size.width + margin && p.y <= size.height + margin }
    private func heading(for point: NativePoint) -> Double {
        if let heading = point.heading { return heading }
        if let previous = model.activePoints.suffix(20).reversed().first(where: { !$0.isBreak && NativePaperGeometry.distance($0, point) > 1 }) {
            return NativePaperGeometry.bearing(from: previous, to: point)
        }
        return 0
    }
    private func initializeCamera(size: CGSize) {
        guard !initialized else { return }; initialized = true
        if let point = model.currentPoint { camera.center = NativePaperPoint(point) }
        else if !model.walks.isEmpty { camera.fit(model.walks.flatMap(\.points), size: size) }
    }
    private func changeZoom(by amount: Double) { followsLocation = false; camera.zoom = min(20, max(3, camera.zoom + amount)); model.haptic() }
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard !pinching else { return }
                if dragOrigin == nil { dragOrigin = camera }
                guard let origin = dragOrigin else { return }
                followsLocation = false
                camera.center.x = origin.center.x - Double(value.translation.width) * origin.metersPerPixel
                camera.center.y = min(NativePaperCamera.halfWorld, max(-NativePaperCamera.halfWorld, origin.center.y + Double(value.translation.height) * origin.metersPerPixel))
            }.onEnded { _ in dragOrigin = nil }
    }
    private func zoomGesture(size: CGSize) -> some Gesture {
        MagnifyGesture().onChanged { value in
            if pinchOrigin == nil { pinchOrigin = camera }
            guard let origin = pinchOrigin else { return }
            pinching = true; followsLocation = false; dragOrigin = nil
            let zoom = min(20, max(3, origin.zoom + log2(max(Double(value.magnification), 0.01))))
            let newMPP = NativePaperCamera.world / (256 * pow(2, zoom))
            let dx = (Double(value.startAnchor.x) - 0.5) * Double(size.width)
            let dy = (Double(value.startAnchor.y) - 0.5) * Double(size.height)
            camera.zoom = zoom
            camera.center.x = origin.center.x + dx * (origin.metersPerPixel - newMPP)
            camera.center.y = min(NativePaperCamera.halfWorld, max(-NativePaperCamera.halfWorld, origin.center.y - dy * (origin.metersPerPixel - newMPP)))
        }.onEnded { _ in pinchOrigin = nil; pinching = false; dragOrigin = nil }
    }
}

private struct NativePaperPoint: Sendable, Equatable {
    var x: Double
    var y: Double
    init(x: Double, y: Double) { self.x = x; self.y = y }
    init(_ point: NativePoint) { self.init(lat: point.lat, lon: point.lon) }
    init(lat: Double, lon: Double) { x = 6378137 * lon * .pi / 180; let latitude = min(85, max(-85, lat)); y = 6378137 * log(tan(.pi / 4 + latitude * .pi / 360)) }
}
private struct NativePaperCamera: Sendable, Equatable {
    static let world = 40075016.68557849
    static let halfWorld = world / 2
    var center = NativePaperPoint(lat: 35.6762, lon: 139.6503)
    var zoom = 16.0
    var metersPerPixel: Double { Self.world / (256 * pow(2, zoom)) }
    func screen(_ p: NativePaperPoint, size: CGSize) -> CGPoint { CGPoint(x: (p.x - center.x) / metersPerPixel + Double(size.width) / 2, y: (center.y - p.y) / metersPerPixel + Double(size.height) / 2) }
    mutating func fit(_ points: [NativePoint], size: CGSize) {
        guard !points.isEmpty else { return }
        let ps = points.map(NativePaperPoint.init)
        let minX = ps.map(\.x).min() ?? 0, maxX = ps.map(\.x).max() ?? 0, minY = ps.map(\.y).min() ?? 0, maxY = ps.map(\.y).max() ?? 0
        center = .init(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let mpp = max(max((maxX - minX) / max(150, Double(size.width) - 80), (maxY - minY) / max(200, Double(size.height) - 320)), 0.7)
        zoom = min(19, max(3, log2(Self.world / (256 * mpp))))
    }
}
private struct NativePaperGeoPoint: Sendable {
    var lat: Double; var lon: Double; var isBreak: Bool; var mode: String
    init(lat: Double, lon: Double, isBreak: Bool, mode: String) { self.lat = lat; self.lon = lon; self.isBreak = isBreak; self.mode = mode }
    init(_ p: NativePoint) { lat = p.lat; lon = p.lon; isBreak = p.isBreak; mode = p.mode }
    var projected: NativePaperPoint { .init(lat: lat, lon: lon) }
}
private struct NativePaperWalkSnapshot: Sendable { var id: String; var points: [NativePaperGeoPoint] }
private struct NativePaperCell: Hashable { var x: Int; var y: Int }
private struct NativePaperTrace: Sendable {
    var walkID: String; var mode: String; var points: [NativePaperPoint]; var width: Double
    var minX: Double; var minY: Double; var maxX: Double; var maxY: Double
    init(walkID: String, mode: String, points: [NativePaperPoint], width: Double) { self.walkID = walkID; self.mode = mode; self.points = points; self.width = width; minX = points.map(\.x).min() ?? 0; minY = points.map(\.y).min() ?? 0; maxX = points.map(\.x).max() ?? 0; maxY = points.map(\.y).max() ?? 0 }
}
private enum NativePaperGeometry {
    static func cell(_ p: NativePaperGeoPoint) -> NativePaperCell {
        let y = Int(floor(p.lat * 111195.08 / 12)); let mid = (Double(y) + 0.5) * 12 / 111195.08
        return .init(x: Int(floor(p.lon * 111195.08 * cos(mid * .pi / 180) / 12)), y: y)
    }
    static func build(_ walks: [NativePaperWalkSnapshot], countVisits: Bool = true) async -> [NativePaperTrace] {
        var visits: [NativePaperCell: Int] = [:]
        if countVisits {
            for walk in walks {
                if Task.isCancelled { return [] }
                var seen = Set<NativePaperCell>()
                for i in walk.points.indices where i > 0 && !walk.points[i].isBreak {
                    let a = walk.points[i - 1], b = walk.points[i]
                    let meters = hypot((a.lon - b.lon) * 111195.08 * cos((a.lat + b.lat) / 2 * .pi / 180), (a.lat - b.lat) * 111195.08)
                    let n = min(1200, max(1, Int(ceil(meters / 6))))
                    for k in 0...n { let t = Double(k) / Double(n); seen.insert(cell(.init(lat: a.lat + (b.lat - a.lat) * t, lon: a.lon + (b.lon - a.lon) * t, isBreak: false, mode: b.mode))) }
                }
                for key in seen { visits[key, default: 0] += 1 }
            }
        }
        var output: [NativePaperTrace] = []
        for walk in walks {
            if Task.isCancelled { return [] }
            var points: [NativePaperPoint] = []; var mode = "walking"; var level = 0
            func flush() { if points.count > 1 { output.append(.init(walkID: walk.id, mode: mode, points: points, width: 1.3 + Double(level) * 0.65)) }; points = [] }
            for i in walk.points.indices where i > 0 {
                let before = walk.points[i - 1], p = walk.points[i]
                if p.isBreak { flush(); continue }
                let visitsCount = visits[cell(p)] ?? 1
                let nextLevel = min(4, max(0, Int(log2(Double(max(1, visitsCount))))))
                if !points.isEmpty && (mode != p.mode || level != nextLevel) { flush() }
                if points.isEmpty { mode = p.mode; level = nextLevel; points.append(before.projected) }
                points.append(p.projected)
            }
            flush()
        }
        return output
    }
    static func activeTraces(_ points: [NativePaperGeoPoint]) async -> [NativePaperTrace] {
        var output: [NativePaperTrace] = [], group: [NativePaperPoint] = [], mode = "walking"
        func flush() { if group.count > 1 { output.append(.init(walkID: "active", mode: mode, points: group, width: 1.9)) }; group = [] }
        for i in points.indices where i > 0 {
            if i.isMultiple(of: 1024), Task.isCancelled { return [] }
            let p = points[i]
            if p.isBreak { flush(); continue }
            if !group.isEmpty && mode != p.mode { flush() }
            if group.isEmpty { mode = p.mode; group.append(points[i - 1].projected) }
            group.append(p.projected)
        }
        flush(); return output
    }
    static func distance(_ a: NativePoint, _ b: NativePoint) -> Double {
        let r = Double.pi / 180, p = sin((b.lat - a.lat) * r / 2), q = sin((b.lon - a.lon) * r / 2)
        return 6371008.8 * 2 * asin(min(1, sqrt(p * p + cos(a.lat * r) * cos(b.lat * r) * q * q)))
    }
    static func bearing(from a: NativePoint, to b: NativePoint) -> Double { let r = Double.pi / 180, dl = (b.lon - a.lon) * r; return atan2(sin(dl) * cos(b.lat * r), cos(a.lat * r) * sin(b.lat * r) - sin(a.lat * r) * cos(b.lat * r) * cos(dl)) / r }
}
/// The clock changes recording labels once per second. Compare only drawing
/// inputs so those label changes do not invalidate thousands of Canvas vertices.
private struct NativePaperCanvas: View, Equatable {
    let saved: [NativePaperTrace]
    let active: [NativePaperTrace]
    let doodles: [NativePaperTrace]
    let geometryRevision: Int
    let camera: NativePaperCamera
    let size: CGSize
    let modes: [String: Bool]
    let ink: Color
    let fade: Bool
    let thicken: Bool
    let dashed: Bool
    let smooth: Bool
    let grid: Bool
    let selection: String?
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.geometryRevision == rhs.geometryRevision && lhs.camera == rhs.camera && lhs.size == rhs.size
            && lhs.modes == rhs.modes && lhs.ink == rhs.ink && lhs.fade == rhs.fade
            && lhs.thicken == rhs.thicken && lhs.dashed == rhs.dashed && lhs.smooth == rhs.smooth
            && lhs.grid == rhs.grid && lhs.selection == rhs.selection
    }
    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, canvasSize in
            if grid { NativePaperPainter.grid(context: &context, size: canvasSize, camera: camera, color: ink.opacity(0.1)) }
            NativePaperPainter.trails(doodles, context: &context, size: canvasSize, camera: camera, color: ink.opacity(0.28), dashed: true, smooth: false, thicken: false, focusedID: nil)
            NativePaperPainter.trails(saved.filter { modes[$0.mode] != false }, context: &context, size: canvasSize, camera: camera, color: ink.opacity(fade ? 0.2 : 0.78), dashed: dashed, smooth: smooth, thicken: thicken, focusedID: selection)
            NativePaperPainter.trails(active.filter { modes[$0.mode] != false }, context: &context, size: canvasSize, camera: camera, color: ink, dashed: dashed, smooth: smooth, thicken: false, focusedID: nil, active: true)
        }
    }
}
private enum NativePaperPainter {
    static func trails(_ traces: [NativePaperTrace], context: inout GraphicsContext, size: CGSize, camera: NativePaperCamera, color: Color, dashed: Bool, smooth: Bool, thicken: Bool, focusedID: String?, active: Bool = false) {
        let mx = camera.metersPerPixel * Double(size.width) / 2, my = camera.metersPerPixel * Double(size.height) / 2
        for trace in traces {
            guard trace.maxX >= camera.center.x - mx, trace.minX <= camera.center.x + mx, trace.maxY >= camera.center.y - my, trace.minY <= camera.center.y + my else { continue }
            let points = trace.points.map { camera.screen($0, size: size) }
            guard let first = points.first else { continue }
            var path = Path(); path.move(to: first)
            if smooth && points.count > 2 {
                for i in 1..<(points.count - 1) { let a = points[i], b = points[i + 1]; path.addQuadCurve(to: .init(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), control: a) }
                path.addLine(to: points[points.count - 1])
            } else { for p in points.dropFirst() { path.addLine(to: p) } }
            let selected = focusedID == nil || focusedID == trace.walkID
            let opacity = focusedID != nil && !selected ? 0.18 : 1.0
            context.stroke(path, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: active ? 1.9 : thicken ? trace.width : 1.3, lineCap: .round, lineJoin: .round, dash: dashed ? [0.5, 4] : []))
        }
    }
    static func grid(context: inout GraphicsContext, size: CGSize, camera: NativePaperCamera, color: Color) {
        let desired = camera.metersPerPixel * 65
        let base = pow(10, floor(log10(max(1, desired))))
        let multiplier = [1.0, 2.0, 5.0, 10.0].first { base * $0 >= desired } ?? 10
        let step = base * multiplier / camera.metersPerPixel
        let x = (Double(size.width) / 2 - camera.center.x / camera.metersPerPixel).truncatingRemainder(dividingBy: step)
        let y = (Double(size.height) / 2 + camera.center.y / camera.metersPerPixel).truncatingRemainder(dividingBy: step)
        var path = Path()
        var gx = x < 0 ? x + step : x
        while gx <= Double(size.width) { path.move(to: .init(x: gx, y: 0)); path.addLine(to: .init(x: gx, y: size.height)); gx += step }
        var gy = y < 0 ? y + step : y
        while gy <= Double(size.height) { path.move(to: .init(x: 0, y: gy)); path.addLine(to: .init(x: size.width, y: gy)); gy += step }
        context.stroke(path, with: .color(color), lineWidth: 0.5)
    }
}

struct NativePaperLineSample: Shape {
    var dashed: Bool
    func path(in rect: CGRect) -> Path { var p = Path(); p.move(to: .init(x: rect.width * 0.12, y: rect.height * 0.7)); p.addCurve(to: .init(x: rect.width * 0.88, y: rect.height * 0.27), control1: .init(x: rect.width * 0.4, y: rect.height * 1.03), control2: .init(x: rect.width * 0.5, y: rect.height * 0.1)); return p }
}
@MainActor private enum NativePaperImageCache {
    static let cache: NSCache<NSString, UIImage> = { let c = NSCache<NSString, UIImage>(); c.countLimit = 80; c.totalCostLimit = 40 * 1024 * 1024; return c }()
    static func image(_ spot: NativeSpot, thumbnail: Bool = false) -> UIImage? {
        guard let bytes = spot.photoData else { return nil }
        let key = "\(spot.id):\(bytes.count):\(thumbnail)" as NSString
        if let image = cache.object(forKey: key) { return image }
        let image: UIImage?
        if thumbnail, let source = CGImageSourceCreateWithData(bytes as CFData, nil),
           let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 128] as CFDictionary) {
            image = UIImage(cgImage: cgImage)
        } else { image = UIImage(data: bytes) }
        guard let image else { return nil }
        cache.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
        return image
    }
}
@MainActor private struct NativePaperPhotoPin: View {
    let spot: NativeSpot; let style: String; let ink: Color
    var body: some View {
        Group {
            if style == "dot" { Circle().fill(ink).frame(width: 8, height: 8).overlay { Circle().stroke(.white, lineWidth: 1) } }
            else if let image = NativePaperImageCache.image(spot, thumbnail: true) {
                let circular = style == "circle" || style == "outline"
                Image(uiImage: image).resizable().scaledToFill().frame(width: 27, height: 29).clipShape(RoundedRectangle(cornerRadius: circular ? 15 : style == "square" ? 1 : 7)).padding(3).background(.white, in: RoundedRectangle(cornerRadius: circular ? 18 : style == "square" ? 2 : 9)).overlay { RoundedRectangle(cornerRadius: circular ? 18 : style == "square" ? 2 : 9).stroke(ink.opacity(style == "outline" ? 0.9 : 0.15), lineWidth: style == "outline" ? 2 : 0.5) }.shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            } else {
                Text(spot.emoji.isEmpty ? "♥" : spot.emoji).font(.system(size: 16)).frame(width: 28, height: 28).foregroundStyle(ink).background(.regularMaterial, in: RoundedRectangle(cornerRadius: style == "square" ? 2 : 10)).overlay { RoundedRectangle(cornerRadius: style == "square" ? 2 : 10).stroke(ink.opacity(0.16), lineWidth: 0.5) }
            }
        }.frame(minWidth: 36, minHeight: 40).contentShape(Rectangle())
    }
}
struct NativePaperCompanion: View {
    var kind: String; var walking = false
    private var fur: Color { switch kind { case "tabby": return Color(red: 0.68, green: 0.43, blue: 0.22); case "silver": return Color(white: 0.55); case "calico": return Color(red: 0.94, green: 0.89, blue: 0.77); default: return Color(white: 0.1) } }
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !walking)) { tick in
            let stride = walking ? sin(tick.date.timeIntervalSinceReferenceDate * 13) * 2 : 0
            ZStack {
                Path { p in p.move(to: .init(x: 15, y: 28)); p.addCurve(to: .init(x: 15, y: 40), control1: .init(x: 29, y: 37), control2: .init(x: 3, y: 41)) }.stroke(fur, style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                ForEach(0..<4) { n in Capsule().fill(fur.opacity(0.9)).frame(width: 4, height: walking ? 10 : 5).offset(x: n.isMultiple(of: 2) ? -8 : 8, y: (n < 2 ? 2 : 12) + (n.isMultiple(of: 2) ? stride : -stride)) }
                Capsule().fill(fur).frame(width: walking ? 17 : 20, height: walking ? 26 : 20).offset(y: walking ? 2 : 4)
                if kind == "tabby" || kind == "silver" { VStack(spacing: 4) { ForEach(0..<3) { _ in Capsule().fill(.black.opacity(0.22)).frame(width: 12, height: 2) } }.offset(y: 3) }
                if kind == "calico" { Ellipse().fill(.black.opacity(0.85)).frame(width: 9, height: 12).offset(x: -3, y: 1); Ellipse().fill(Color.brown).frame(width: 8, height: 9).offset(x: 4, y: 8) }
                Circle().fill(fur).frame(width: 18, height: 17).offset(y: -11)
                HStack(spacing: 6) { RoundedRectangle(cornerRadius: 1).fill(fur).frame(width: 6, height: 7).rotationEffect(.degrees(-22)); RoundedRectangle(cornerRadius: 1).fill(fur).frame(width: 6, height: 7).rotationEffect(.degrees(22)) }.offset(y: -19)
            }.frame(width: 28, height: 44)
        }.accessibilityHidden(true)
    }
}
@MainActor private struct NativeMapSpotPreview: View {
    let spot: NativeSpot
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView { VStack(alignment: .leading, spacing: 16) {
                if let image = NativePaperImageCache.image(spot) { Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 24)); ShareLink(item: Image(uiImage: image), preview: SharePreview(spot.text.isEmpty ? "ここいいな" : spot.text, image: Image(uiImage: image))) { Label("写真を共有", systemImage: "square.and.arrow.up") } }
                else { Text(spot.emoji.isEmpty ? "♥" : spot.emoji).font(.system(size: 60)).frame(maxWidth: .infinity).padding(.vertical, 40) }
                Text(spot.text.isEmpty ? "ここいいな" : spot.text).font(.title3.weight(.semibold))
                Text(Date(timeIntervalSince1970: spot.point.t / 1000), format: .dateTime.year().month().day().hour().minute()).font(.footnote).foregroundStyle(.secondary)
            }.padding(20) }.navigationTitle("ここいいな").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } } }
        }
    }
}
@MainActor private struct NativeMapFlagPreview: View {
    @ObservedObject var model: NativeAppModel
    let flag: NativeFlag
    @State private var removalError: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack { ScrollView { VStack(spacing: 16) {
            Image(systemName: "flag.fill").font(.system(size: 36)).padding(.top, 8)
            Text(flag.name).font(.title2.weight(.semibold))
            if let current = model.currentPoint { Text("現在地から \(model.distanceText(NativePaperGeometry.distance(current, flag.point))) \(model.distanceUnit)").foregroundStyle(.secondary) }
            ShareLink(item: "\(flag.name)\nhttps://www.openstreetmap.org/?mlat=\(flag.point.lat)&mlon=\(flag.point.lon)#map=17/\(flag.point.lat)/\(flag.point.lon)") { Label("場所を共有", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent)
            Button("旗を取り下げる", role: .destructive) {
                do {
                    try model.updateLibrary { library in
                        library["flags"] = (library["flags"] as? [[String: Any]] ?? []).filter { $0["id"] as? String != flag.id }
                    }
                    model.haptic(); dismiss()
                } catch { removalError = error.localizedDescription }
            }.buttonStyle(.bordered).frame(minHeight: 44)
        }.padding(20) }.navigationTitle("目的地").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } } } }
        .presentationDetents([.medium])
        .alert("旗を取り下げられませんでした", isPresented: Binding(get: { removalError != nil }, set: { if !$0 { removalError = nil } })) {
            Button("閉じる", role: .cancel) { removalError = nil }
        } message: { Text(removalError ?? "") }
    }
}
