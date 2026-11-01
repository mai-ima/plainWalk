import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Only an explicit EXIF offset or a complete GPS UTC date makes a capture
/// timestamp absolute. A camera's local clock alone is never interpreted as UTC.
struct NativePhotoMetadata: Sendable {
    struct Coordinate: Sendable, Equatable { let lat: Double; let lon: Double }
    let capturedAt: Double?
    let captureLocal: String?
    let captureOffset: String?
    let captureSubsecond: String?
    private let gpsCaptureLocal: String?
    private let gpsCaptureSubsecond: String?
    let coordinate: Coordinate?
    let cameraMake: String?
    let cameraModel: String?
    let lensModel: String?
    let exposure: Double?
    let aperture: Double?
    let focalLength: Double?
    let iso: [Double]

    init(data: Data) {
        let source = CGImageSourceCreateWithData(data as CFData, nil)
        let properties = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [String: Any] } ?? [:]
        self.init(properties: properties)
    }
    init(properties: [String: Any]) {
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let local = Self.text(exif[kCGImagePropertyExifDateTimeOriginal as String])
        let offset = Self.text(exif[kCGImagePropertyExifOffsetTimeOriginal as String])
        captureLocal = local.flatMap { Self.validLocal($0) ? $0 : nil }
        captureOffset = offset.flatMap { Self.offsetSeconds($0) != nil ? $0 : nil }
        captureSubsecond = captureLocal == nil ? nil : Self.subsecond(exif[kCGImagePropertyExifSubsecTimeOriginal as String])
        if let absolute = Self.absolute(local: local, offset: offset) {
            let fraction = captureSubsecond.flatMap { Double("0." + $0) } ?? 0
            capturedAt = nativeTime(absolute + fraction * 1000)
            gpsCaptureLocal = nil; gpsCaptureSubsecond = nil
        } else {
            capturedAt = Self.gpsTime(gps)
            if capturedAt != nil, let day = gps[kCGImagePropertyGPSDateStamp as String] as? String,
               let time = gps[kCGImagePropertyGPSTimeStamp as String] as? String {
                let pieces = time.split(separator: ".", maxSplits: 1)
                gpsCaptureLocal = day + " " + String(pieces[0])
                gpsCaptureSubsecond = pieces.count > 1 ? Self.subsecond(String(pieces[1])) : nil
            } else { gpsCaptureLocal = nil; gpsCaptureSubsecond = nil }
        }
        if let lat = nativeNumber(gps[kCGImagePropertyGPSLatitude as String]), (0...85).contains(lat),
           let lon = nativeNumber(gps[kCGImagePropertyGPSLongitude as String]), (0...180).contains(lon),
           let north = gps[kCGImagePropertyGPSLatitudeRef as String] as? String, ["N", "S"].contains(north),
           let east = gps[kCGImagePropertyGPSLongitudeRef as String] as? String, ["E", "W"].contains(east) {
            coordinate = Coordinate(lat: north == "S" ? -lat : lat, lon: east == "W" ? -lon : lon)
        } else { coordinate = nil }
        cameraMake = Self.text(tiff[kCGImagePropertyTIFFMake as String])
        cameraModel = Self.text(tiff[kCGImagePropertyTIFFModel as String])
        lensModel = Self.text(exif[kCGImagePropertyExifLensModel as String])
        exposure = Self.positive(exif[kCGImagePropertyExifExposureTime as String], upper: 86_400)
        aperture = Self.positive(exif[kCGImagePropertyExifFNumber as String], upper: 1_000)
        focalLength = Self.positive(exif[kCGImagePropertyExifFocalLength as String], upper: 100_000)
        iso = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Any] ?? []).prefix(16).compactMap { Self.positive($0, upper: 10_000_000) }
    }
    var json: [String: Any] {
        var result: [String: Any] = [:]
        if let capturedAt { result["capturedAt"] = capturedAt }
        if let captureLocal { result["captureLocal"] = captureLocal }
        if let captureOffset { result["captureOffset"] = captureOffset }
        if let captureSubsecond { result["captureSubsecond"] = captureSubsecond }
        if let cameraMake { result["cameraMake"] = cameraMake }
        if let cameraModel { result["cameraModel"] = cameraModel }
        if let lensModel { result["lensModel"] = lensModel }
        if let exposure { result["exposure"] = exposure }
        if let aperture { result["aperture"] = aperture }
        if let focalLength { result["focalLength"] = focalLength }
        if !iso.isEmpty { result["iso"] = iso }
        return result
    }
    /// The image has already been rotated into display orientation. GPS, serial
    /// numbers, MakerNote, thumbnails and arbitrary user comments are not copied.
    var jpegProperties: [String: Any] {
        var exif: [String: Any] = [:], tiff: [String: Any] = [:]
        if let captureLocal { exif[kCGImagePropertyExifDateTimeOriginal as String] = captureLocal }
        if let captureOffset { exif[kCGImagePropertyExifOffsetTimeOriginal as String] = captureOffset }
        if let captureSubsecond { exif[kCGImagePropertyExifSubsecTimeOriginal as String] = captureSubsecond }
        // Copy the validated GPS UTC clock and its original decimal digits,
        // rather than round-tripping it through Date/Double and losing precision.
        if let gpsCaptureLocal {
            exif[kCGImagePropertyExifDateTimeOriginal as String] = gpsCaptureLocal
            exif[kCGImagePropertyExifOffsetTimeOriginal as String] = "+00:00"
            if let gpsCaptureSubsecond { exif[kCGImagePropertyExifSubsecTimeOriginal as String] = gpsCaptureSubsecond }
            else { exif.removeValue(forKey: kCGImagePropertyExifSubsecTimeOriginal as String) }
        }
        if let lensModel { exif[kCGImagePropertyExifLensModel as String] = lensModel }
        if let exposure { exif[kCGImagePropertyExifExposureTime as String] = exposure }
        if let aperture { exif[kCGImagePropertyExifFNumber as String] = aperture }
        if let focalLength { exif[kCGImagePropertyExifFocalLength as String] = focalLength }
        if !iso.isEmpty { exif[kCGImagePropertyExifISOSpeedRatings as String] = iso }
        if let cameraMake { tiff[kCGImagePropertyTIFFMake as String] = cameraMake }
        if let cameraModel { tiff[kCGImagePropertyTIFFModel as String] = cameraModel }
        var properties: [String: Any] = [kCGImagePropertyOrientation as String: 1]
        if !exif.isEmpty { properties[kCGImagePropertyExifDictionary as String] = exif }
        if !tiff.isEmpty { properties[kCGImagePropertyTIFFDictionary as String] = tiff }
        return properties
    }
    func inferredPoint(in trails: [[NativePoint]]) -> NativePoint? {
        guard let capturedAt else { return nil }
        var candidate: NativePoint?
        func accepts(_ point: NativePoint) -> Bool {
            if let previous = candidate { return NativeTrackMath.distance(previous, point) <= 1 }
            candidate = point; return true
        }
        for points in trails {
            // Never sort a corrupt timeline into a plausible-looking route.
            guard points.allSatisfy({ $0.t.isFinite && abs($0.t) <= 8_640_000_000_000_000 }),
                  zip(points, points.dropFirst()).allSatisfy({ $0.t < $1.t }) else { continue }
            for (index, b) in points.enumerated() {
                guard abs(b.lat) <= 85, abs(b.lon) <= 180, b.lat.isFinite, b.lon.isFinite,
                      (b.accuracy ?? 0) >= 0, (b.accuracy ?? 0) <= 100 else { continue }
                if b.t == capturedAt {
                    if !accepts(NativePoint(lat: b.lat, lon: b.lon, t: capturedAt)) { return nil }
                    continue
                }
                guard index > 0 else { continue }
                let a = points[index - 1], interval = b.t - a.t
                guard !b.isBreak, a.t < capturedAt, capturedAt < b.t,
                      interval > 0, interval <= 120_000,
                      a.lat.isFinite, a.lon.isFinite, abs(a.lat) <= 85, abs(a.lon) <= 180,
                      (a.accuracy ?? 0) >= 0, (a.accuracy ?? 0) <= 100 else { continue }
                let distance = NativeTrackMath.distance(a, b)
                guard distance <= 1_000, distance / (interval / 1000) <= 45 else { continue }
                let fraction = (capturedAt - a.t) / interval
                var delta = b.lon - a.lon
                if delta > 180 { delta -= 360 }; if delta < -180 { delta += 360 }
                var longitude = a.lon + fraction * delta
                if longitude > 180 { longitude -= 360 }; if longitude < -180 { longitude += 360 }
                let point = NativePoint(lat: a.lat + fraction * (b.lat - a.lat), lon: longitude, t: capturedAt)
                if !accepts(point) { return nil }
            }
        }
        // Multiple overlapping walks are usable only when they agree on place.
        return candidate
    }
    private static func text(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty, text.utf16.count <= 200 else { return nil }; return text
    }
    private static func subsecond(_ value: Any?) -> String? {
        guard let text = value as? String, (1...9).contains(text.utf8.count),
              text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return text
    }
    private static func positive(_ value: Any?, upper: Double) -> Double? {
        guard let number = nativeNumber(value), number > 0, number <= upper else { return nil }; return number
    }
    private static func offsetSeconds(_ text: String) -> Int? {
        if text == "Z" { return 0 }
        guard text.range(of: "^[+-][0-9]{2}:[0-9]{2}$", options: .regularExpression) != nil else { return nil }
        let h = Int(text.dropFirst().prefix(2)) ?? 99, m = Int(text.suffix(2)) ?? 99
        guard h <= 14, m < 60, h < 14 || m == 0 else { return nil }
        return (text.hasPrefix("-") ? -1 : 1) * (h * 3600 + m * 60)
    }
    private static func date(_ local: String, offset: Int) -> Date? {
        guard local.range(of: "^[0-9]{4}:[0-9]{2}:[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$", options: .regularExpression) != nil else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: offset)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"; formatter.isLenient = false
        guard let date = formatter.date(from: local), formatter.string(from: date) == local else { return nil }; return date
    }
    private static func validLocal(_ text: String) -> Bool { date(text, offset: 0) != nil }
    private static func absolute(local: String?, offset: String?) -> Double? {
        guard let local, let offset, let seconds = offsetSeconds(offset), let date = date(local, offset: seconds) else { return nil }
        return nativeTime(date.timeIntervalSince1970 * 1000)
    }
    private static func gpsTime(_ gps: [String: Any]) -> Double? {
        guard let day = gps[kCGImagePropertyGPSDateStamp as String] as? String,
              let time = gps[kCGImagePropertyGPSTimeStamp as String] as? String,
              time.range(of: "^[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,9})?$", options: .regularExpression) != nil else { return nil }
        let parts = time.split(separator: ".", maxSplits: 1)
        guard let date = date(day + " " + String(parts[0]), offset: 0) else { return nil }
        let fraction = parts.count > 1 ? Double("0." + parts[1]) ?? 0 : 0
        return nativeTime((date.timeIntervalSince1970 + fraction) * 1000)
    }
    #if DEBUG
    static func selfTest() throws -> Bool {
        func require(_ result: @autoclosure () -> Bool, _ label: String) throws {
            if !result() { throw NativeError.message("写真メタデータの検証に失敗: " + label) }
        }
        let expected = ISO8601DateFormatter().date(from: "2026-10-12T01:30:00Z")!.timeIntervalSince1970 * 1000
        let exif: [String: Any] = [kCGImagePropertyExifDateTimeOriginal as String: "2026:10:12 10:30:00",
                                  kCGImagePropertyExifOffsetTimeOriginal as String: "+09:00",
                                  kCGImagePropertyExifExposureTime as String: 1.0 / 125,
                                  kCGImagePropertyExifFNumber as String: 1.8,
                                  kCGImagePropertyExifISOSpeedRatings as String: [100],
                                  kCGImagePropertyExifUserComment as String: "do not copy this"]
        let gps: [String: Any] = [kCGImagePropertyGPSLatitude as String: 35.68, kCGImagePropertyGPSLatitudeRef as String: "N",
                                 kCGImagePropertyGPSLongitude as String: 139.76, kCGImagePropertyGPSLongitudeRef as String: "E",
                                 kCGImagePropertyGPSDateStamp as String: "2026:10:12", kCGImagePropertyGPSTimeStamp as String: "01:30:00"]
        let properties: [String: Any] = [kCGImagePropertyExifDictionary as String: exif,
                                       kCGImagePropertyGPSDictionary as String: gps,
                                       kCGImagePropertyTIFFDictionary as String: [kCGImagePropertyTIFFMake as String: "Fixture", kCGImagePropertyTIFFModel as String: "Synthetic camera"]]
        let metadata = Self(properties: properties)
        try require(metadata.capturedAt == expected && metadata.coordinate == Coordinate(lat: 35.68, lon: 139.76), "time offset and GPS")
        var localOnly = exif; localOnly.removeValue(forKey: kCGImagePropertyExifOffsetTimeOriginal as String)
        let unknownZone = Self(properties: [kCGImagePropertyExifDictionary as String: localOnly])
        try require(unknownZone.capturedAt == nil && unknownZone.captureLocal != nil, "unknown offset is not UTC")
        var invalidDate = exif; invalidDate[kCGImagePropertyExifDateTimeOriginal as String] = "2026:02:30 10:30:00"
        try require(Self(properties: [kCGImagePropertyExifDictionary as String: invalidDate]).capturedAt == nil, "impossible date")
        var invalidOffset = exif; invalidOffset[kCGImagePropertyExifOffsetTimeOriginal as String] = "+14:01"
        try require(Self(properties: [kCGImagePropertyExifDictionary as String: invalidOffset]).capturedAt == nil, "invalid offset")
        var fractionalGPS = gps; fractionalGPS[kCGImagePropertyGPSTimeStamp as String] = "01:30:00.250"
        try require(Self(properties: [kCGImagePropertyGPSDictionary as String: fractionalGPS]).capturedAt == expected + 250, "GPS UTC fraction")
        var invalidGPS = gps; invalidGPS[kCGImagePropertyGPSLatitude as String] = true
        try require(Self(properties: [kCGImagePropertyGPSDictionary as String: invalidGPS]).coordinate == nil, "boolean coordinate")
        invalidGPS = gps; invalidGPS.removeValue(forKey: kCGImagePropertyGPSLongitudeRef as String)
        try require(Self(properties: [kCGImagePropertyGPSDictionary as String: invalidGPS]).coordinate == nil, "missing hemisphere")
        let safe = metadata.jpegProperties
        try require(safe[kCGImagePropertyGPSDictionary as String] == nil && safe[kCGImagePropertyOrientation as String] as? Int == 1,
                    "embedded GPS removed and pixels orientation normalized")
        try require((safe[kCGImagePropertyExifDictionary as String] as? [String: Any])?[kCGImagePropertyExifUserComment as String] == nil,
                    "arbitrary private metadata excluded")

        // Exercise ImageIO's actual JPEG metadata encoding and decoding.
        let sample = try NativePhotoEffects.sampleJPEG()
        func fixtureJPEG(_ properties: [String: Any]) throws -> Data {
            guard let source = CGImageSourceCreateWithData(sample as CFData, nil),
                  let output = CFDataCreateMutable(kCFAllocatorDefault, 0),
                  let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw NativeError.message("写真メタデータの JPEG 試験を作成できません。")
            }
            CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw NativeError.message("JPEG 試験の保存に失敗しました。") }
            return output as Data
        }
        let fixture = try fixtureJPEG(properties), decoded = Self(data: fixture)
        try require(decoded.capturedAt == expected && decoded.coordinate == metadata.coordinate && decoded.cameraModel == "Synthetic camera", "ImageIO round trip")
        let filtered = try NativePhotoEffects.jpeg(fixture, film: "grayscale(1)", lut: nil, intensity: 1)
        let preserved = Self(data: filtered)
        try require(preserved.capturedAt == expected && preserved.cameraModel == decoded.cameraModel && preserved.coordinate == nil,
                    "real CoreImage transform preserves useful EXIF without embedded GPS")

        var subsecondExif = exif; subsecondExif[kCGImagePropertyExifSubsecTimeOriginal as String] = "123"
        var subsecondProperties = properties; subsecondProperties[kCGImagePropertyExifDictionary as String] = subsecondExif
        let fractionalExifJPEG = try fixtureJPEG(subsecondProperties)
        let fractionalExif = Self(data: fractionalExifJPEG)
        try require(fractionalExif.capturedAt == expected + 123 && fractionalExif.json["captureSubsecond"] as? String == "123", "EXIF milliseconds round trip")
        let fractionalFiltered = try NativePhotoEffects.jpeg(fractionalExifJPEG, film: "grayscale(1)", lut: nil, intensity: 1)
        try require(Self(data: fractionalFiltered).capturedAt == expected + 123, "EXIF milliseconds survive CoreImage")
        for bad in ["", "1234567890", ".123", "12x", "１２３"] {
            subsecondExif[kCGImagePropertyExifSubsecTimeOriginal as String] = bad
            let invalid = Self(properties: [kCGImagePropertyExifDictionary as String: subsecondExif])
            try require(invalid.captureSubsecond == nil && invalid.capturedAt == expected, "invalid fractional EXIF is ignored")
        }
        let gpsOnly = Self(properties: [kCGImagePropertyGPSDictionary as String: fractionalGPS])
        let normalizedGPSJPEG = try fixtureJPEG(gpsOnly.jpegProperties)
        let normalizedGPS = Self(data: normalizedGPSJPEG)
        try require(normalizedGPS.capturedAt == expected + 250 && normalizedGPS.captureSubsecond == "250" && normalizedGPS.coordinate == nil,
                    "GPS UTC milliseconds become GPS-free UTC EXIF")
        let gpsFiltered = try NativePhotoEffects.jpeg(normalizedGPSJPEG, film: "grayscale(1)", lut: nil, intensity: 1)
        try require(Self(data: gpsFiltered).capturedAt == expected + 250, "GPS UTC milliseconds survive CoreImage")

        let a = NativePoint(lat: 35.68, lon: 139.76, t: expected - 30_000, accuracy: 5)
        var b = NativePoint(lat: 35.682, lon: 139.762, t: expected + 30_000, accuracy: 5)
        guard let middle = metadata.inferredPoint(in: [[a, b]]) else { throw NativeError.message("写真とさんぽの時刻を照合できません。") }
        try require(abs(middle.lat - 35.681) < 0.000001 && middle.t == expected, "bounded interpolation")
        let parallel = [NativePoint(lat: a.lat + 0.01, lon: a.lon, t: a.t), NativePoint(lat: b.lat + 0.01, lon: b.lon, t: b.t)]
        try require(metadata.inferredPoint(in: [[a, b], parallel]) == nil, "conflicting overlapping walks are ambiguous")
        try require(metadata.inferredPoint(in: [[a, b], [a, b]]) != nil, "agreeing overlapping walks deduplicate")
        try require(metadata.inferredPoint(in: [[b, a]]) == nil, "reversed timeline is not sorted into a route")
        let fast = [NativePoint(lat: 35.68, lon: 139.76, t: expected - 500), NativePoint(lat: 35.681, lon: 139.76, t: expected + 500)]
        try require(metadata.inferredPoint(in: [fast]) == nil, "implausible interpolation speed")
        b.isBreak = true
        try require(metadata.inferredPoint(in: [[a, b]]) == nil, "never connect a recording gap")
        b.isBreak = false; b.t = expected + 180_000
        try require(metadata.inferredPoint(in: [[a, b]]) == nil, "never infer across a long missing interval")
        try require(metadata.inferredPoint(in: [[a], [NativePoint(lat: 35.682, lon: 139.762, t: expected + 30_000)]]) == nil,
                    "never connect separate walks")
        try require(unknownZone.inferredPoint(in: [[a, b]]) == nil, "no inferred route from an ambiguous local clock")
        return true
    }
    #endif
}
