import Foundation

/// Independent 12 m approximation, not a reconstruction of the original formula.
/// Each previously unvisited cell contributes its largest continuous passage's
/// 16-direction diameter. The projection is <= the true passage diameter, with
/// at most 1 - cos(pi/32) (<0.49%) directional loss. Curves remain a cell approximation.
enum NativeTrackMath {
    private static let earthRadius = 6_371_008.8
    private static let metersPerLatitudeDegree = 111_195.08
    private static let directions = (0..<16).map { index in
        (cos(Double(index) * .pi / 16), sin(Double(index) * .pi / 16))
    }
    private static func valid(_ point: NativePoint) -> Bool {
        point.lat.isFinite && point.lon.isFinite && abs(point.lat) <= 85 && abs(point.lon) <= 180
    }
    static func distance(_ a: NativePoint, _ b: NativePoint) -> Double {
        guard valid(a), valid(b) else { return 0 }
        let rad = Double.pi / 180
        let latitude = (b.lat - a.lat) * rad, longitude = (b.lon - a.lon) * rad
        let term = pow(sin(latitude / 2), 2) + cos(a.lat * rad) * cos(b.lat * rad) * pow(sin(longitude / 2), 2)
        return earthRadius * 2 * asin(min(1, sqrt(max(0, term))))
    }
    static func trailDistance(_ points: [NativePoint]) -> Double {
        guard points.count > 1 else { return 0 }
        return (1..<points.count).reduce(0) { total, index in
            total + (points[index].isBreak ? 0 : distance(points[index - 1], points[index]))
        }
    }
    private static func normalizedLongitude(_ value: Double) -> Double {
        let remainder = (value + 180).truncatingRemainder(dividingBy: 360)
        return (remainder < 0 ? remainder + 360 : remainder) - 180
    }
    private static func longitudeDelta(_ a: Double, _ b: Double) -> Double {
        let delta = b - a
        return delta > 180 ? delta - 360 : delta < -180 ? delta + 360 : delta
    }
    private static func pointCell(_ point: NativePoint) -> String {
        let row = Int(floor(point.lat * metersPerLatitudeDegree / 12))
        let mid = (Double(row) + 0.5) * 12 / metersPerLatitudeDegree
        let column = Int(floor(normalizedLongitude(point.lon) * metersPerLatitudeDegree * cos(mid * .pi / 180) / 12))
        return "\(row):\(column)"
    }
    private struct Piece {
        let key: String; let start: Double; let end: Double
        let scale: Double; let shift: Double; let dLat: Double; let dLon: Double
    }
    /// Row slabs have a fixed latitude-scaled longitude width. Exact intersections
    /// replace point sampling, so adding collinear GPS points cannot skip cells.
    private static func gridPieces(_ a: NativePoint, _ b: NativePoint, visit: (Piece) -> Void) {
        guard valid(a), valid(b) else { return }
        let meters = distance(a, b)
        guard meters > 0, meters <= 50_000 else { return }
        let dLat = b.lat - a.lat, dLon = longitudeDelta(a.lon, b.lon)
        let y0 = a.lat * metersPerLatitudeDegree, y1 = b.lat * metersPerLatitudeDegree
        var cuts = [0.0, 1.0]
        if y0 != y1 {
            let lower = Int(floor(min(y0, y1) / 12)) + 1, upper = Int(ceil(max(y0, y1) / 12))
            if lower < upper { for k in lower..<upper {
                let t = (Double(k) * 12 - y0) / (y1 - y0)
                if t > 0 && t < 1 { cuts.append(t) }
            } }
        }
        if dLon != 0 { for seam in [-180.0, 180.0] {
            let t = (seam - a.lon) / dLon
            if t > 0 && t < 1 { cuts.append(t) }
        } }
        cuts.sort()
        for index in 1..<cuts.count {
            let ta = cuts[index - 1], tb = cuts[index]
            guard tb - ta >= 1e-12 else { continue }
            let midT = (ta + tb) / 2
            let row = Int(floor((a.lat + dLat * midT) * metersPerLatitudeDegree / 12))
            let midLat = (Double(row) + 0.5) * 12 / metersPerLatitudeDegree
            let scale = metersPerLatitudeDegree * cos(midLat * .pi / 180)
            let rawMid = a.lon + dLon * midT, shift = normalizedLongitude(rawMid) - rawMid
            let xa = (a.lon + dLon * ta + shift) * scale, xb = (a.lon + dLon * tb + shift) * scale
            var columns = [ta, tb]
            if xa != xb {
                let lower = Int(floor(min(xa, xb) / 12)) + 1, upper = Int(ceil(max(xa, xb) / 12))
                if lower < upper { for k in lower..<upper {
                    let t = ta + (Double(k) * 12 - xa) / (xb - xa) * (tb - ta)
                    if t > ta && t < tb { columns.append(t) }
                } }
            }
            columns.sort()
            for columnIndex in 1..<columns.count {
                let start = columns[columnIndex - 1], end = columns[columnIndex]
                guard end - start >= 1e-12 else { continue }
                let column = Int(floor((a.lon + dLon * ((start + end) / 2) + shift) * scale / 12))
                visit(Piece(key: "\(row):\(column)", start: start, end: end, scale: scale, shift: shift, dLat: dLat, dLon: dLon))
            }
        }
    }
    static func cellKeys(_ a: NativePoint, _ b: NativePoint) -> Set<String> {
        guard valid(a), valid(b), distance(a, b) <= 50_000 else { return [] }
        var cells = Set<String>()
        gridPieces(a, b) { cells.insert($0.key) }
        if cells.isEmpty { cells.insert(pointCell(a)) }
        return cells
    }

    struct Accumulator {
        private let visited: Set<String>
        private let dayStart: Double
        private let dayEnd: Double
        private var best: [String: Double] = [:]
        private var passage: Passage?
        private var walked = 0.0
        private(set) var total = 0.0
        private(set) var dayTotal = 0.0
        private(set) var cells = Set<String>()
        private struct Passage {
            let key: String; let originX: Double; let originY: Double
            var minimum = Array(repeating: 0.0, count: 16)
            var maximum = Array(repeating: 0.0, count: 16)
        }
        init(visited: Set<String> = [], day: Date = Date()) {
            self.visited = visited
            let range = Calendar.current.dateInterval(of: .day, for: day)
            dayStart = (range?.start ?? day).timeIntervalSince1970 * 1000
            dayEnd = (range?.end ?? day).timeIntervalSince1970 * 1000
        }
        mutating func resetPassage() { passage = nil }
        mutating func append(_ a: NativePoint, _ b: NativePoint) {
            guard NativeTrackMath.valid(a), NativeTrackMath.valid(b), !b.isBreak,
                  NativeTrackMath.distance(a, b) <= 50_000 else { resetPassage(); return }
            walked += NativeTrackMath.distance(a, b)
            NativeTrackMath.gridPieces(a, b) { piece in
                appendPiece(piece, from: a, to: b)
            }
        }
        private mutating func appendPiece(_ piece: Piece, from a: NativePoint, to b: NativePoint) {
            cells.insert(piece.key)
            guard !visited.contains(piece.key) else { resetPassage(); return }
            let dt = b.t - a.t
            var cuts = [piece.start, piece.end]
            // Only the queried day's two boundaries matter. Even a corrupt file
            // with centuries between fixes cannot create an unbounded day loop.
            if a.t.isFinite, b.t.isFinite, dt > 0 { for boundary in [dayStart, dayEnd] {
                let t = (boundary - a.t) / dt
                if t > piece.start && t < piece.end { cuts.append(t) }
            } }
            cuts.sort()
            for index in 1..<cuts.count {
                let ta = cuts[index - 1], tb = cuts[index]
                let x0 = (a.lon + piece.dLon * ta + piece.shift) * piece.scale
                let y0 = (a.lat + piece.dLat * ta) * NativeTrackMath.metersPerLatitudeDegree
                let x1 = (a.lon + piece.dLon * tb + piece.shift) * piece.scale
                let y1 = (a.lat + piece.dLat * tb) * NativeTrackMath.metersPerLatitudeDegree
                var current = passage?.key == piece.key ? passage! : Passage(key: piece.key, originX: x0, originY: y0)
                var diameter = 0.0
                for direction in 0..<16 {
                    let vector = NativeTrackMath.directions[direction]
                    let startProjection = (x0-current.originX)*vector.0+(y0-current.originY)*vector.1
                    let endProjection = (x1-current.originX)*vector.0+(y1-current.originY)*vector.1
                    current.minimum[direction] = min(current.minimum[direction],startProjection,endProjection)
                    current.maximum[direction] = max(current.maximum[direction],startProjection,endProjection)
                    diameter = max(diameter, current.maximum[direction] - current.minimum[direction])
                }
                passage = current
                let previous = best[piece.key] ?? 0
                if diameter > previous {
                    best[piece.key] = diameter
                    let p0 = NativePoint(lat: a.lat + piece.dLat * ta, lon: NativeTrackMath.normalizedLongitude(a.lon + piece.dLon * ta), t: 0)
                    let p1 = NativePoint(lat: a.lat + piece.dLat * tb, lon: NativeTrackMath.normalizedLongitude(a.lon + piece.dLon * tb), t: 0)
                    let delta = min(diameter - previous, NativeTrackMath.distance(p0, p1), max(0, walked - total))
                    total += delta
                    let timestamp = dt > 0 && dt.isFinite ? a.t + dt * ((ta + tb) / 2) : b.t
                    if timestamp >= dayStart && timestamp < dayEnd { dayTotal += delta }
                }
            }
        }
    }
    struct Summary {
        var byWalk: [String: Double] = [:]
        var cells = Set<String>()
        var total = 0.0
        var dayTotal = 0.0
    }
    // The accumulator's read-only history Set must be released before the next
    // formUnion. This helper avoids keeping a COW alias to the entire history
    // alive across each saved walk, including in unoptimised Simulator builds.
    private static func contribution(_ walk: NativeWalk, visited: Set<String>, day: Date) -> (cells: Set<String>, total: Double, dayTotal: Double) {
        var accumulator = Accumulator(visited: visited, day: day)
        if walk.points.count > 1 { for index in 1..<walk.points.count {
            accumulator.append(walk.points[index - 1], walk.points[index])
        } }
        return (accumulator.cells,accumulator.total,accumulator.dayTotal)
    }
    static func summary(_ walks: [NativeWalk], day: Date = Date(), visited: Set<String> = []) -> Summary {
        var output = Summary();output.cells=visited
        for walk in walks.sorted(by: { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }) {
            let addition=contribution(walk,visited:output.cells,day:day)
            output.byWalk[walk.id] = addition.total
            output.cells.formUnion(addition.cells)
            output.total += addition.total; output.dayTotal += addition.dayTotal
        }
        return output
    }
    static func exploration(_ walks: [NativeWalk]) -> [String: Double] { summary(walks).byWalk }

    #if DEBUG
    static func selfTest() throws -> Bool {
        func check(_ value: Bool, _ name: String) throws { if !value { throw NativeError.message("Native exploration: " + name) } }
        let origin = NativePoint(lat: 35, lon: 139, t: 0)
        let north = NativePoint(lat: 35.001, lon: 139, t: 1000)
        let meters = distance(origin, north)
        try check(abs(meters - 111.195) < 0.1 && abs(trailDistance([origin, north]) - meters) < 0.001, "geodesic distance")
        var separated = north; separated.isBreak = true
        try check(trailDistance([origin, separated]) == 0, "distance crossed a recording gap")
        func run(_ points: [NativePoint], visited: Set<String> = [], day: Date = Date()) -> Accumulator {
            var accumulator = Accumulator(visited: visited, day: day)
            for index in points.indices.dropFirst() { accumulator.append(points[index - 1], points[index]) }
            return accumulator
        }
        let longitude = 139 + 1000 / (metersPerLatitudeDegree * cos(35 * .pi / 180))
        let sparse = [origin, NativePoint(lat: 35, lon: longitude, t: 100_000)]
        let reference = run(sparse)
        for count in [100, 200, 300] {
            let points = (0...count).map { i in NativePoint(lat: 35, lon: 139 + (longitude - 139) * Double(i) / Double(count), t: Double(i) * 100_000 / Double(count)) }
            try check(abs(run(points).total - reference.total) < 0.001, "GPS sampling density changed exploration")
        }
        try check(abs(reference.total - 1000) < 0.001 && reference.total <= trailDistance(sparse) + 1e-8, "first straight road distance")
        for (angle, expected) in [(5.625, 995.1794604570179), (45.0, 999.9805162985023), (90.0, 1000.0)] {
            let radians = angle * .pi / 180
            let deltaLat = 1000 * sin(radians) / metersPerLatitudeDegree
            let deltaLon = 1000 * cos(radians) / (metersPerLatitudeDegree * cos(35 * .pi / 180))
            var baseline: Double?
            for count in [1,100,200,300] {
                let points = (0...count).map { i in NativePoint(lat: 35 + deltaLat * Double(i) / Double(count), lon: 139 + deltaLon * Double(i) / Double(count), t: Double(i) * 100_000 / Double(count)) }
                let result = run(points)
                if let baseline {try check(abs(result.total-baseline)<0.001,"angled line changed with GPS density")}
                else {baseline=result.total;try check(abs(result.total-expected)<0.00001,"Web/Swift numerical fixture diverged")}
                try check(result.total <= trailDistance(points)+1e-8,"exploration exceeded walking distance")
                try check(result.total >= trailDistance(points)*cos(.pi/32)-0.01,"directional error exceeded 0.49 percent")
                try check(abs(run(points+Array(points.dropLast().reversed())).total-result.total)<0.001,"angled return increased exploration")
            }
        }
        let short = [origin,NativePoint(lat:35,lon:139+1/(metersPerLatitudeDegree*cos(35 * .pi/180)),t:1000)]
        try check(abs(run(short).total-1)<0.00001,"one metre route became a twelve metre cell")
        try check(abs(run(sparse + [origin]).total - reference.total) < 0.001, "returning increased exploration")
        try check(run(sparse, visited: reference.cells).total == 0, "visited road counted as new")
        let first = NativeWalk(json: ["id": "first", "start": 0.0, "end": 100_000.0, "points": sparse.map(\.json)])!
        let repeatWalk = NativeWalk(json: ["id": "repeat", "start": 200_000.0, "end": 300_000.0, "points": sparse.reversed().map(\.json)])!
        let explored = summary([repeatWalk, first])
        try check(abs((explored.byWalk["first"] ?? 0) - reference.total) < 0.001 && explored.byWalk["repeat"] == 0, "chronology")
        let west = NativePoint(lat: 0, lon: 179.9999), east = NativePoint(lat: 0, lon: -179.9999)
        let seam = cellKeys(west, east)
        try check(!seam.isEmpty && seam.count <= 10 && seam.allSatisfy { abs(Int($0.split(separator: ":")[1]) ?? 0) > 1_000_000 }, "antimeridian crossed the long way")
        try check(cellKeys(origin, NativePoint(lat: -35, lon: -139)).isEmpty && cellKeys(origin, NativePoint(lat: .nan, lon: 139)).isEmpty, "unbounded or invalid jump")
        // Two disconnected 1 m passages in opposite corners of one cell must
        // never create a 10 m chord between the disconnected points.
        let small = [NativePoint(lat: 0.00001, lon: 0.00001, t: 0), NativePoint(lat: 0.00001, lon: 0.000019, t: 1000), NativePoint(lat: 0.00009, lon: 0.00008, t: 2000, isBreak: true), NativePoint(lat: 0.00009, lon: 0.000089, t: 3000)]
        var repeatedStart=small[0];repeatedStart.isBreak=true
        let repeatedSmall=small+[repeatedStart]+Array(small.dropFirst())
        try check(run(small).total <= 1.01 && run(repeatedSmall).total <= 1.01, "disconnected cell passages made an imaginary chord")
        let calendar = Calendar.current, midnight = calendar.startOfDay(for: Date())
        let start = midnight.addingTimeInterval(-60).timeIntervalSince1970 * 1000
        let overnight = [NativePoint(lat: 35, lon: 139, t: start), NativePoint(lat: 35, lon: longitude, t: start + 120_000)]
        let yesterday = calendar.date(byAdding: .day, value: -1, to: midnight)!
        let prior = run(overnight, day: yesterday), today = run(overnight, day: midnight)
        try check(abs(prior.dayTotal + today.dayTotal - today.total) < 0.001 && abs(prior.dayTotal - 500) < 0.01, "midnight allocation")
        for count in [100,300] {
            let points=(0...count).map { i in NativePoint(lat:35,lon:139+(longitude-139)*Double(i)/Double(count),t:start+120_000*Double(i)/Double(count)) }
            let densePrior=run(points,day:yesterday),denseToday=run(points,day:midnight)
            try check(abs(densePrior.dayTotal-prior.dayTotal)<0.001 && abs(denseToday.dayTotal-today.dayTotal)<0.001,"day split changed with GPS density")
            try check(abs(densePrior.dayTotal+denseToday.dayTotal-denseToday.total)<0.001,"daily portions did not sum to total")
        }
        return true
    }
    #endif
}
