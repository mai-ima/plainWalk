import Foundation

/// Independent implementation of the documented approximate 12 m exploration grid.
enum NativeTrackMath {
    private static let earthRadius = 6_371_008.8
    private static let metersPerLatitudeDegree = 111_195.08

    private static func valid(_ point: NativePoint) -> Bool {
        point.lat.isFinite && point.lon.isFinite && abs(point.lat) <= 85 && abs(point.lon) <= 180
    }

    static func distance(_ a: NativePoint, _ b: NativePoint) -> Double {
        guard valid(a), valid(b) else { return 0 }
        let rad = Double.pi / 180
        let latitude = (b.lat - a.lat) * rad
        let longitude = (b.lon - a.lon) * rad
        let term = pow(sin(latitude / 2), 2) + cos(a.lat * rad) * cos(b.lat * rad) * pow(sin(longitude / 2), 2)
        return earthRadius * 2 * asin(min(1, sqrt(max(0, term))))
    }

    static func trailDistance(_ points: [NativePoint]) -> Double {
        guard points.count > 1 else { return 0 }
        var total = 0.0
        for index in 1..<points.count where !points[index].isBreak {
            total += distance(points[index - 1], points[index])
        }
        return total
    }

    /// Invalid/imported transcontinental jumps never allocate millions of samples.
    static func cellKeys(_ a: NativePoint, _ b: NativePoint) -> Set<String> {
        guard valid(a), valid(b) else { return [] }
        let meters = distance(a, b)
        guard meters <= 50_000 else { return [] }
        let count = max(1, Int(ceil(meters / 3)))
        var longitudeDelta = b.lon - a.lon
        if longitudeDelta > 180 { longitudeDelta -= 360 }
        if longitudeDelta < -180 { longitudeDelta += 360 }
        var keys = Set<String>()
        keys.reserveCapacity(min(count + 1, 5_000))
        for index in 0...count {
            let fraction = Double(index) / Double(count)
            let latitude = a.lat + (b.lat - a.lat) * fraction
            var longitude = a.lon + longitudeDelta * fraction
            if longitude > 180 { longitude -= 360 }
            if longitude < -180 { longitude += 360 }
            let row = Int(floor(latitude * metersPerLatitudeDegree / 12))
            let midLatitude = (Double(row) + 0.5) * 12 / metersPerLatitudeDegree
            let column = Int(floor(longitude * metersPerLatitudeDegree * cos(midLatitude * .pi / 180) / 12))
            keys.insert("\(row):\(column)")
        }
        return keys
    }

    static func exploration(_ walks: [NativeWalk]) -> [String: Double] {
        var explored = Set<String>()
        var totals: [String: Double] = [:]
        for walk in walks.sorted(by: { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }) {
            var newMeters = 0.0
            if walk.points.count > 1 {
                for index in 1..<walk.points.count where !walk.points[index].isBreak {
                    let before = walk.points[index - 1], point = walk.points[index]
                    let keys = cellKeys(before, point)
                    guard !keys.isEmpty else { continue }
                    let fresh = keys.reduce(0) { $0 + (explored.contains($1) ? 0 : 1) }
                    newMeters += distance(before, point) * Double(fresh) / Double(keys.count)
                    explored.formUnion(keys)
                }
            }
            totals[walk.id, default: 0] += newMeters
        }
        return totals
    }

    #if DEBUG
    static func selfTest() throws -> Bool {
        let origin = NativePoint(lat: 35, lon: 139, t: 0)
        let north = NativePoint(lat: 35.001, lon: 139, t: 1000)
        let meters = distance(origin, north)
        guard abs(meters - 111.195) < 0.1, abs(trailDistance([origin, north]) - meters) < 0.001 else {
            throw NativeError.message("Native trail distance calculation failed.")
        }
        var separated = north
        separated.isBreak = true
        guard trailDistance([origin, separated]) == 0 else { throw NativeError.message("Trail distance crossed a recording gap.") }
        let first = NativeWalk(json: ["id": "first", "start": 0.0, "end": 1000.0, "points": [origin.json, north.json]])!
        let repeatWalk = NativeWalk(json: ["id": "repeat", "start": 2000.0, "end": 3000.0, "points": [north.json, origin.json]])!
        let explored = exploration([repeatWalk, first])
        guard abs((explored["first"] ?? 0) - meters) < 0.001, explored["repeat"] == 0 else {
            throw NativeError.message("Exploration chronology or repeated-road deduplication failed.")
        }
        let west = NativePoint(lat: 0, lon: 179.9999)
        let east = NativePoint(lat: 0, lon: -179.9999)
        let seam = cellKeys(west, east)
        guard !seam.isEmpty, seam.count <= 10, seam.allSatisfy({ abs(Int($0.split(separator: ":")[1]) ?? 0) > 1_000_000 }) else {
            throw NativeError.message("Exploration cells crossed the long side of the antimeridian.")
        }
        guard cellKeys(origin, NativePoint(lat: -35, lon: -139)).isEmpty,
              cellKeys(origin, NativePoint(lat: .nan, lon: 139)).isEmpty else {
            throw NativeError.message("Exploration accepted an invalid or unbounded imported segment.")
        }
        return true
    }
    #endif
}
