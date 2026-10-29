import Foundation

/// Licensed Japan municipality outlines, shared with Web area badges. Loading and
/// projection happen once on this actor, never inside a Canvas frame or GPS tick.
actor NativeBoundaryGeometry {
    static let shared = NativeBoundaryGeometry()
    private var cached: Snapshot?

    struct Point: Sendable, Equatable {
        let x: Double
        let y: Double
        init(lat: Double, lon: Double) {
            x = 6_378_137 * lon * .pi / 180
            y = 6_378_137 * log(tan(.pi / 4 + lat * .pi / 360))
        }
    }
    struct Bounds: Sendable {
        let minX: Double; let minY: Double; let maxX: Double; let maxY: Double
        func intersects(minX x1: Double, minY y1: Double, maxX x2: Double, maxY y2: Double) -> Bool {
            maxX >= x1 && minX <= x2 && maxY >= y1 && minY <= y2
        }
    }
    struct Ring: Sendable {
        let points: [Point]
        let medium: [Point]
        let coarse: [Point]
        let bounds: Bounds
    }
    struct Snapshot: Sendable {
        let rings: [Ring]
        let featureCount: Int
    }

    func load() throws -> Snapshot {
        if let cached { return cached }
        #if PLAYGROUNDS
        let root = Bundle.module.url(forResource: "Web", withExtension: nil)
        #else
        let root = Bundle.main.url(forResource: "Web", withExtension: nil)
        #endif
        guard let root else { throw NativeError.message("日本の境界データが見つかりません。アプリを更新してください。") }
        let snapshot = try Self.parse(Data(contentsOf: root.appendingPathComponent("data/japan-municipalities.geojson")))
        guard snapshot.featureCount > 0, !snapshot.rings.isEmpty else { throw NativeError.message("日本の境界データを読み込めませんでした。") }
        cached = snapshot
        return snapshot
    }

    nonisolated static func parse(_ data: Data) throws -> Snapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["type"] as? String == "FeatureCollection", let features = root["features"] as? [[String: Any]],
              features.count <= 20_000 else { throw NativeError.message("境界データの形式が正しくありません。") }
        var rings: [Ring] = []
        var count = 0
        var vertexBudget = 2_000_000
        for feature in features {
            guard let geometry = feature["geometry"] as? [String: Any] else { continue }
            let polygons: [[[[Double]]]]
            switch geometry["type"] as? String {
            case "Polygon": polygons = (geometry["coordinates"] as? [[[Double]]]).map { [$0] } ?? []
            case "MultiPolygon": polygons = geometry["coordinates"] as? [[[[Double]]]] ?? []
            default: continue
            }
            let oldCount = rings.count
            for polygon in polygons {
                for coordinates in polygon {
                    vertexBudget -= coordinates.count
                    guard vertexBudget >= 0 else { throw NativeError.message("境界データが大きすぎます。") }
                    // Invalid vertices invalidate a whole ring. Removing a bad
                    // vertex would invent a connecting edge across that gap.
                    guard coordinates.count >= 4, coordinates.allSatisfy({ p in
                        p.count >= 2 && p[0].isFinite && p[1].isFinite && abs(p[0]) <= 180 && abs(p[1]) <= 85
                    }), let first = coordinates.first, let last = coordinates.last,
                        first[0] == last[0], first[1] == last[1] else { continue }
                    var points: [Point] = []
                    for coordinate in coordinates {
                        let point = Point(lat: coordinate[1], lon: coordinate[0])
                        if points.last != point { points.append(point) }
                    }
                    guard points.count >= 4, Set(points.dropLast().map { "\($0.x),\($0.y)" }).count >= 3 else { continue }
                    let bounds = Bounds(minX: points.map(\.x).min()!, minY: points.map(\.y).min()!, maxX: points.map(\.x).max()!, maxY: points.map(\.y).max()!)
                    rings.append(Ring(points: points, medium: simplifyClosed(points, tolerance: 100), coarse: simplifyClosed(points, tolerance: 600), bounds: bounds))
                }
            }
            if rings.count > oldCount { count += 1 }
        }
        return Snapshot(rings: rings, featureCount: count)
    }

    /// Iterative Douglas–Peucker avoids recursion on long coasts. Treat the two
    /// halves of a closed ring separately so its equal endpoints do not collapse.
    nonisolated private static func simplifyClosed(_ points: [Point], tolerance: Double) -> [Point] {
        guard points.count > 5 else { return points }
        let split = (points.count - 1) / 2
        func simplify(_ slice: ArraySlice<Point>) -> [Point] {
            let input = Array(slice)
            guard input.count > 2 else { return input }
            var keep = Set([0, input.count - 1]), stack = [(0, input.count - 1)]
            let limit = tolerance * tolerance
            while let (start, end) = stack.popLast() {
                guard end > start + 1 else { continue }
                let a = input[start], b = input[end], dx = b.x - a.x, dy = b.y - a.y
                let length = dx * dx + dy * dy
                var maximum = limit, chosen: Int?
                for index in (start + 1)..<end {
                    let p = input[index]
                    let t = length > 0 ? min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length)) : 0
                    let px = p.x - a.x - t * dx, py = p.y - a.y - t * dy
                    let distance = px * px + py * py
                    if distance > maximum { maximum = distance; chosen = index }
                }
                if let index = chosen { keep.insert(index); stack.append((start, index)); stack.append((index, end)) }
            }
            return keep.sorted().map { input[$0] }
        }
        let a = simplify(points[0...split]), b = simplify(points[split...(points.count - 1)])
        let output = a + b.dropFirst()
        // Tiny islands remain a closed polygon rather than becoming a line.
        return output.count >= 4 ? output : points
    }

    #if DEBUG
    nonisolated static func selfTest() throws -> Bool {
        func check(_ value: Bool, _ message: String) throws { if !value { throw NativeError.message("Boundary geometry: " + message) } }
        let fixture = """
        {"type":"FeatureCollection","features":[
          {"geometry":{"type":"Polygon","coordinates":[[[139,35],[140,35],[140,36],[139,36],[139,35]],[[139.2,35.2],[139.3,35.2],[139.3,35.3],[139.2,35.2]]]}},
          {"geometry":{"type":"MultiPolygon","coordinates":[[[[141,35],[142,35],[142,36],[141,35]]]]}},
          {"geometry":{"type":"Polygon","coordinates":[[[139,35],[140,35],[140,86],[139,35]]]}},
          {"geometry":{"type":"Polygon","coordinates":[[[139,35],[140,35],[140,36],[139,34]]]}}
        ]}
        """
        let snapshot = try parse(Data(fixture.utf8))
        try check(snapshot.featureCount == 2 && snapshot.rings.count == 3, "holes / islands / invalid ring handling")
        for ring in snapshot.rings {
            try check(ring.points.first == ring.points.last && ring.medium.first == ring.medium.last && ring.coarse.first == ring.coarse.last, "closed coast became open")
            try check(ring.bounds.intersects(minX: ring.points[0].x, minY: ring.points[0].y, maxX: ring.points[0].x, maxY: ring.points[0].y), "viewport culling rejected edge")
            try check(!ring.bounds.intersects(minX: -1, minY: -1, maxX: 1, maxY: 1), "viewport culling retained remote area")
        }
        var coordinates = (0..<360).map { index -> [Double] in
            let angle = Double(index) * .pi / 180
            return [139 + cos(angle) * 0.1, 35 + sin(angle) * 0.1]
        }
        coordinates.append(coordinates[0])
        let denseData = try JSONSerialization.data(withJSONObject: ["type": "FeatureCollection", "features": [["geometry": ["type": "Polygon", "coordinates": [coordinates]]]]])
        let dense = try parse(denseData)
        try check(dense.rings.count == 1, "dense island was rejected")
        let island = dense.rings[0]
        try check(island.coarse.count >= 4 && island.coarse.count < island.points.count, "coast simplification did not preserve a polygon")
        // Bound the visual error in projected metres, independently of vertex count.
        for point in island.points {
            var nearest = Double.infinity
            for index in 1..<island.coarse.count {
                let a = island.coarse[index - 1], b = island.coarse[index]
                let dx = b.x - a.x, dy = b.y - a.y, length = dx * dx + dy * dy
                let t = length > 0 ? min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy) / length)) : 0
                nearest = min(nearest, hypot(point.x - a.x - t * dx, point.y - a.y - t * dy))
            }
            try check(nearest <= 600.001, "simplified coast exceeded its error bound")
        }
        return true
    }
    #endif
}
