import Foundation

/// Periodic horizontal coordinates belong to the rendering camera, not to the
/// stored GPS data. Keep a short route across ±180° in one local world copy.
enum NativeMapProjection {
    static let world = 2 * Double.pi * 6_378_137

    static func delta(_ value: Double, period: Double = world) -> Double {
        var result = value.truncatingRemainder(dividingBy: period)
        if result > period / 2 { result -= period }
        if result < -period / 2 { result += period }
        return result
    }

    static func nearest(_ value: Double, to reference: Double, period: Double = world) -> Double {
        reference + delta(value - reference, period: period)
    }

    struct Arc {
        let lowerBound: Double
        let upperBound: Double
        var center: Double { (lowerBound + upperBound) / 2 }
        var width: Double { upperBound - lowerBound }
    }

    /// Cut the circle at its largest empty gap. This also works for independent
    /// tracks separated by a break; joining input order would invent a journey.
    static func minimumArc(_ values: [Double], period: Double = world) -> Arc? {
        let points = values.filter(\.isFinite).map { value -> Double in
            let remainder = value.truncatingRemainder(dividingBy: period)
            return remainder < 0 ? remainder + period : remainder
        }.sorted()
        guard let first = points.first, let last = points.last else { return nil }
        var gap = first + period - last
        var lower = first
        for index in points.indices.dropFirst() {
            let candidate = points[index] - points[index - 1]
            if candidate > gap { gap = candidate; lower = points[index] }
        }
        return Arc(lowerBound: lower, upperBound: lower + period - gap)
    }

    static func shift(minX: Double, maxX: Double, near reference: Double) -> Double {
        let center = (minX + maxX) / 2
        return nearest(center, to: reference) - center
    }
}
