import Foundation

struct NativeDoodleCompletion {
    let doodleID: String
    let pointIndices: [Int]
}

/// Index planned drawing coordinates, then only check cells around each accepted GPS fix.
/// The caller advances the cached revision after saving these exact completion patches.
@MainActor final class NativeDoodleProgress {
    private struct Candidate {
        let doodleID: String
        let pointIndex: Int
        let point: NativePoint
        let created: Double
    }
    private var indexedRevision: Int?
    private var buckets: [String: [Candidate]] = [:]
    private let degreesPerCell = 0.001
    func didApply(revision: Int) { indexedRevision = revision }
    func reset() { indexedRevision = nil; buckets.removeAll(keepingCapacity: false) }
    func completedPoints(in doodles: [[String: Any]], at point: NativePoint, revision: Int) -> [NativeDoodleCompletion] {
        guard !point.isBreak, let accuracy = point.accuracy, accuracy.isFinite, accuracy >= 0, accuracy <= 40, point.lat.isFinite, point.lon.isFinite, point.t.isFinite, abs(point.lat) <= 85, abs(point.lon) <= 180 else { return [] }
        if indexedRevision != revision { build(doodles, revision: revision) }
        let x = Int(floor(point.lon / degreesPerCell)), y = Int(floor(point.lat / degreesPerCell))
        let longitudeRadius = max(1, Int(ceil(15 / (111_320 * max(0.08, cos(point.lat * .pi / 180)) * degreesPerCell))))
        var completed: [String: [Int]] = [:]
        let current = Dictionary(doodles.compactMap { raw -> (String, [[String: Any]])? in guard let id = raw["id"] as? String else { return nil }; return (id, raw["points"] as? [[String: Any]] ?? []) }, uniquingKeysWith: { first, _ in first })
        for cellY in (y - 1)...(y + 1) {
            for cellX in (x - longitudeRadius)...(x + longitudeRadius) {
                for candidate in buckets["\(cellX),\(cellY)"] ?? [] {
                    guard point.t >= candidate.created, let points = current[candidate.doodleID], candidate.pointIndex < points.count, points[candidate.pointIndex]["done"] as? Bool != true, NativeTrackMath.distance(candidate.point, point) <= 15 else { continue }
                    completed[candidate.doodleID, default: []].append(candidate.pointIndex)
                }
            }
        }
        return completed.map { NativeDoodleCompletion(doodleID: $0.key, pointIndices: $0.value.sorted()) }
    }
    private func build(_ doodles: [[String: Any]], revision: Int) {
        buckets.removeAll(keepingCapacity: true)
        for doodle in doodles {
            guard let id = doodle["id"] as? String, let created = nativeNumber(doodle["created"]) else { continue }
            for (index, raw) in (doodle["points"] as? [[String: Any]] ?? []).enumerated() {
                guard raw["done"] as? Bool != true, let point = NativePoint(json: raw) else { continue }
                let key = "\(Int(floor(point.lon / degreesPerCell))),\(Int(floor(point.lat / degreesPerCell)))"
                buckets[key, default: []].append(Candidate(doodleID: id, pointIndex: index, point: point, created: created))
            }
        }
        indexedRevision = revision
    }
    static func applying(_ completions: [NativeDoodleCompletion], to doodles: [[String: Any]]) -> [[String: Any]] {
        let patches = Dictionary(completions.map { ($0.doodleID, $0.pointIndices) }, uniquingKeysWith: { $0 + $1 })
        return doodles.map { original in
            guard let id = original["id"] as? String, let indices = patches[id], var points = original["points"] as? [[String: Any]] else { return original }
            for index in indices where points.indices.contains(index) { points[index]["done"] = true }
            var result = original; result["points"] = points; return result
        }
    }
}
