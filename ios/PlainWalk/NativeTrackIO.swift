import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// GPX/TCX exchange without JavaScript, network requests or external XML entities.
enum NativeTrackIO {
    static func parse(data: Data, fileName: String) throws -> [[String: Any]] {
        guard !data.isEmpty, data.count <= 20 * 1024 * 1024 else {
            throw TrackError.message("20 MB 以下の GPX / TCX ファイルを選んでください。")
        }
        // Inspect ASCII markup even in UTF-16/UTF-32 documents before XMLParser sees a DTD.
        let markup = String(decoding: data.filter { $0 != 0 }, as: UTF8.self)
        guard markup.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
              markup.range(of: "<!ENTITY", options: .caseInsensitive) == nil else {
            throw TrackError.message("外部参照や DTD を含む XML は取り込めません。")
        }
        let reader = TrackReader()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), reader.failure == nil else {
            throw reader.failure ?? TrackError.message("GPX / TCX の XML を読み取れませんでした。")
        }
        guard reader.recognizedRoot else { throw TrackError.message("GPX / TCX のファイルを選んでください。") }
        let groups = reader.groups.filter { !$0.points.isEmpty }
        guard !groups.isEmpty else { throw TrackError.message("有効な位置情報がありません。緯度・経度を含む GPX / TCX を選んでください。") }
        let importedAt = Date().timeIntervalSince1970 * 1000
        let base = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        return groups.enumerated().map { index, group in
            let times = interpolatedTimes(group.points.map { $0.time }, importedAt: importedAt)
            let points: [[String: Any]] = group.points.enumerated().map { i, point in
                ["lat": point.latitude, "lon": point.longitude, "t": times[i],
                 "break": point.isBreak, "mode": group.mode]
            }
            let fallback = base.isEmpty ? "取り込んださんぽ" : String(base.prefix(120))
            let name = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return ["id": "import-" + UUID().uuidString, "name": name.isEmpty ? fallback + (groups.count > 1 ? " \(index + 1)" : "") : String(name.prefix(120)),
                    "start": times[0], "end": times[times.count - 1],
                    "duration": times[times.count - 1] - times[0], "points": points,
                    "note": "", "source": "import", "importedAt": importedAt]
        }
    }

    static func gpx(walks: [NativeWalk]) -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><gpx version=\"1.1\" creator=\"PlainWalk\" xmlns=\"http://www.topografix.com/GPX/1/1\">"
        for walk in walks {
            var track = "<trk><name>\(escapeXML(walk.name))</name>"
            if !walk.note.isEmpty { track += "<desc>\(escapeXML(walk.note))</desc>" }
            let modes = Set(walk.points.map { $0.mode })
            if modes.count == 1, let mode = modes.first { track += "<type>\(escapeXML(mode))</type>" }
            var segmentOpen = false
            var hasPoint = false
            var disconnected = false
            for point in walk.points {
                guard point.lat.isFinite, point.lon.isFinite, abs(point.lat) <= 85, abs(point.lon) <= 180,
                      point.t.isFinite, point.t >= -62_135_596_800_000, point.t <= 253_402_300_799_999 else {
                    disconnected = true
                    continue
                }
                if !segmentOpen || point.isBreak || disconnected {
                    if segmentOpen { track += "</trkseg>" }
                    track += "<trkseg>"
                    segmentOpen = true
                }
                disconnected = false
                let time = formatter.string(from: Date(timeIntervalSince1970: point.t / 1000))
                track += "<trkpt lat=\"\(point.lat)\" lon=\"\(point.lon)\"><time>\(time)</time></trkpt>"
                hasPoint = true
            }
            if segmentOpen { track += "</trkseg>" }
            if hasPoint { xml += track + "</trk>" }
        }
        xml += "</gpx>"
        return Data(xml.utf8)
    }

    #if DEBUG
    static func selfTest() throws -> Bool {
        func read(_ xml: String) throws -> [[String: Any]] { try parse(data: Data(xml.utf8), fileName: "test.gpx") }
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw TrackError.message("Native track IO: " + message) }
        }
        func rejects(_ xml: String) throws {
            var rejected = false
            do { _ = try read(xml) } catch { rejected = true }
            try check(rejected, "invalid XML was accepted")
        }
        let xml = "<gpx><trk><name>Epoch &amp; trail</name><trkseg><trkpt lat=\"35\" lon=\"139\"><time>1970-01-01T00:00:00Z</time></trkpt><trkpt lat=\"35.0001\" lon=\"139\"/><trkpt lat=\"35.0002\" lon=\"139\"><time>1970-01-01T00:00:02Z</time></trkpt></trkseg><trkseg><trkpt lat=\"35.0003\" lon=\"139\"><time>1970-01-01T00:00:03Z</time></trkpt></trkseg></trk></gpx>"
        let imported = try read(xml)
        let points = imported.first?["points"] as? [[String: Any]] ?? []
        try check(points.count == 4 && (points[3]["break"] as? Bool) == true, "segment boundary disappeared")
        try check((points.first?["t"] as? Double) == 0 && (points[1]["t"] as? Double) == 1000, "epoch zero or missing timestamp changed")
        var library = NativeStore.emptyLibrary; library["walks"] = imported
        try NativeStore.validate(library)
        var named = imported[0]; named["name"] = "<&\"'さんぽ"; named["note"] = "A & B"
        guard let walk = NativeWalk(json: named) else { throw TrackError.message("Native track IO: imported walk is invalid") }
        let output = gpx(walks: [walk])
        let encoded = String(decoding: output, as: UTF8.self)
        try check(encoded.components(separatedBy: "<trkseg>").count == 3 && encoded.contains("&amp;"), "GPX escaping or segments failed")
        let roundtrip = try parse(data: output, fileName: "again.gpx")
        try check((roundtrip.first?["name"] as? String) == (named["name"] as? String), "XML name roundtrip failed")
        let broken = try read("<gpx><rte><rtept lat=\"35\" lon=\"139\"/><rtept lat=\"NaN\" lon=\"139\"/><rtept lat=\"35.001\" lon=\"139\"/></rte></gpx>")
        let repaired = broken.first?["points"] as? [[String: Any]] ?? []
        try check(repaired.count == 2 && (repaired[1]["break"] as? Bool) == true, "invalid coordinate created an imaginary road")
        let reversed = try read("<gpx><rte><rtept lat=\"35\" lon=\"139\"><time>1970-01-01T00:00:02Z</time></rtept><rtept lat=\"35.001\" lon=\"139\"><time>1970-01-01T00:00:01Z</time></rtept></rte></gpx>")
        try check((reversed[0]["end"] as? Double ?? 0) > (reversed[0]["start"] as? Double ?? 0), "clock reversal was not repaired")
        let tcx = try read("<TrainingCenterDatabase xmlns=\"http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2\"><Activities><Activity Sport=\"Biking\"><Lap><Track><Trackpoint><Time>1970-01-01T09:00:00+09:00</Time><Position><LatitudeDegrees>35</LatitudeDegrees><LongitudeDegrees>139</LongitudeDegrees></Position></Trackpoint></Track></Lap></Activity></Activities></TrainingCenterDatabase>")
        let cycling = tcx.first?["points"] as? [[String: Any]] ?? []
        try check(cycling.count == 1 && (cycling[0]["mode"] as? String) == "cycling" && (cycling[0]["t"] as? Double) == 0, "namespaced TCX, timezone or transport failed")
        try rejects("<gpx><trk><trkseg><trkpt lat=\"35\" lon=\"139\"><time>2026-02-30T00:00:00Z</time></trkpt></trkseg></trk></gpx>")
        try rejects("<gpx><trk><trkseg><trkpt lat=\"\" lon=\"139\"/></trkseg></trk></gpx>")
        try rejects("<gpx><trk>")
        try rejects("<!DOCTYPE gpx [<!ENTITY x SYSTEM \"file:///etc/passwd\">]><gpx><trk><name>&x;</name></trk></gpx>")
        return true
    }
    #endif

    private static func escapeXML(_ text: String) -> String {
        let legal = String(String.UnicodeScalarView(text.unicodeScalars.filter {
            $0.value == 9 || $0.value == 10 || $0.value == 13 ||
            ($0.value >= 0x20 && $0.value != 0xFFFE && $0.value != 0xFFFF)
        }))
        return legal.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Preserve valid anchors, interpolate missing samples, then repair duplicate/reversed clocks.
    private static func interpolatedTimes(_ raw: [Double?], importedAt: Double) -> [Double] {
        guard !raw.isEmpty else { return [] }
        var anchors: [(Int, Double)] = []
        for (index, time) in raw.enumerated() {
            guard let time else { continue }
            let previous = anchors.last
            let fixed = previous.map { max(time, $0.1 + Double(index - $0.0)) } ?? time
            anchors.append((index, fixed))
        }
        guard let first = anchors.first, let last = anchors.last else {
            return raw.indices.map { importedAt - Double(raw.count - 1 - $0) * 1000 }
        }
        var result = Array(repeating: 0.0, count: raw.count)
        for index in 0...first.0 { result[index] = first.1 - Double(first.0 - index) * 1000 }
        if anchors.count > 1 {
            for a in 1..<anchors.count {
                let before = anchors[a - 1], after = anchors[a]
                let step = (after.1 - before.1) / Double(after.0 - before.0)
                for index in (before.0 + 1)...after.0 { result[index] = before.1 + Double(index - before.0) * step }
            }
        }
        if last.0 + 1 < raw.count {
            for index in (last.0 + 1)..<raw.count { result[index] = last.1 + Double(index - last.0) * 1000 }
        }
        return result
    }

    fileprivate enum TrackError: LocalizedError {
        case message(String)
        var errorDescription: String? { switch self { case .message(let message): return message } }
    }

    private struct TrackPoint {
        var latitude: Double
        var longitude: Double
        var time: Double?
        var isBreak: Bool
    }
    private struct TrackGroup {
        var name = ""
        var mode = "walking"
        var points: [TrackPoint] = []
    }
    private struct PendingPoint {
        var latitude: String?
        var longitude: String?
        var time: String?
    }

    private final class TrackReader: NSObject, XMLParserDelegate {
        var groups: [TrackGroup] = []
        var failure: TrackError?
        var recognizedRoot = false
        private var root = ""
        private var elements: [String] = []
        private var text = ""
        private var group: TrackGroup?
        private var groupDepth = 0
        private var point: PendingPoint?
        private var pointDepth = 0
        private var needsBreak = false
        private var pointCount = 0
        private var groupCount = 0
        private let numberExpression = try? NSRegularExpression(pattern: "^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?$")
        private let timeExpression = try? NSRegularExpression(pattern: "^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\\.([0-9]{1,9}))?(Z|[+-][0-9]{2}:[0-9]{2})$")

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
            let tag = elementName.lowercased()
            elements.append(tag)
            text = ""
            guard elements.count <= 64 else { stop(parser, "XML の階層が深すぎます。"); return }
            if elements.count == 1 {
                root = tag
                recognizedRoot = tag == "gpx" || tag == "trainingcenterdatabase"
                if !recognizedRoot { stop(parser, "GPX / TCX のファイルを選んでください。") }
                return
            }
            let parent = elements.dropLast().last
            let startsGPX = root == "gpx" && (tag == "trk" || tag == "rte") && parent == "gpx"
            let startsTCX = root == "trainingcenterdatabase" && (tag == "activity" || tag == "course") && (parent == "activities" || parent == "courses")
            if startsGPX || startsTCX {
                guard group == nil else { stop(parser, "記録の XML 構造が不正です。"); return }
                groupCount += 1
                guard groupCount <= 10_000 else { stop(parser, "記録の数が多すぎます。"); return }
                group = TrackGroup()
                groupDepth = elements.count
                needsBreak = false
                if let sport = attributes["Sport"]?.lowercased() {
                    group?.mode = sport == "running" ? "running" : sport == "biking" ? "cycling" : "walking"
                }
            }
            guard group != nil else { return }
            if (tag == "trkseg" && parent == "trk") || (tag == "track" && root == "trainingcenterdatabase") {
                needsBreak = !(group?.points.isEmpty ?? true)
            }
            let startsPoint = (root == "gpx" && ((tag == "trkpt" && parent == "trkseg") || (tag == "rtept" && parent == "rte"))) ||
                (root == "trainingcenterdatabase" && tag == "trackpoint" && parent == "track")
            if startsPoint {
                guard point == nil else { stop(parser, "記録点の XML 構造が不正です。"); return }
                pointCount += 1
                guard pointCount <= 100_000 else { stop(parser, "1 ファイルは 10 万点までです。分割して取り込んでください。"); return }
                point = PendingPoint(latitude: attributes["lat"], longitude: attributes["lon"])
                pointDepth = elements.count
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard let tag = elements.last, ["time", "name", "latitudedegrees", "longitudedegrees", "type"].contains(tag) else { return }
            guard text.utf8.count + string.utf8.count <= 16_384 else { stop(parser, "記録の文字列が長すぎます。"); return }
            text += string
        }
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            guard let value = String(data: CDATABlock, encoding: .utf8) else { stop(parser, "XML の文字を読み取れません。"); return }
            self.parser(parser, foundCharacters: value)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let tag = elementName.lowercased()
            guard elements.last == tag else { stop(parser, "XML の構造が不正です。"); return }
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let parent = elements.dropLast().last
            if point != nil {
                if tag == "time" && elements.count == pointDepth + 1 { point?.time = value }
                if parent == "position" && elements.count == pointDepth + 2 {
                    if tag == "latitudedegrees" { point?.latitude = value }
                    if tag == "longitudedegrees" { point?.longitude = value }
                }
                if elements.count == pointDepth { finishPoint() }
            } else if group != nil && elements.count == groupDepth + 1 {
                if tag == "name" { group?.name = value }
                if tag == "type", root == "gpx" {
                    if ["running", "run"].contains(value.lowercased()) { group?.mode = "running" }
                    if ["cycling", "biking", "bicycle"].contains(value.lowercased()) { group?.mode = "cycling" }
                    if ["vehicle", "driving", "automotive"].contains(value.lowercased()) { group?.mode = "vehicle" }
                }
            }
            if group != nil && elements.count == groupDepth {
                if let group { groups.append(group) }
                group = nil
            }
            elements.removeLast()
            text = ""
        }

        private func finishPoint() {
            defer { point = nil }
            guard let pending = point,
                  let latitude = strictNumber(pending.latitude), let longitude = strictNumber(pending.longitude),
                  abs(latitude) <= 85, abs(longitude) <= 180 else { needsBreak = true; return }
            var time: Double?
            if let raw = pending.time {
                guard let parsed = isoTime(raw) else { needsBreak = true; return }
                time = parsed
            }
            let isBreak = needsBreak && !(group?.points.isEmpty ?? true)
            group?.points.append(TrackPoint(latitude: latitude, longitude: longitude, time: time, isBreak: isBreak))
            needsBreak = false
        }
        private func strictNumber(_ raw: String?) -> Double? {
            guard let raw else { return nil }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.utf8.count <= 64,
                  numberExpression?.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil,
                  let number = Double(value), number.isFinite else { return nil }
            return number
        }
        private func isoTime(_ value: String) -> Double? {
            // Avoid permissive DateFormatter normalization, locale dependence and unspecified time zones.
            guard value.utf8.count <= 40,
                  let match = timeExpression?.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
            let input = value as NSString
            func capture(_ n: Int) -> String { let range = match.range(at: n); return range.location == NSNotFound ? "" : input.substring(with: range) }
            guard let year = Int(capture(1)), year >= 1, let month = Int(capture(2)), (1...12).contains(month),
                  let day = Int(capture(3)), (1...31).contains(day), let hour = Int(capture(4)), (0...23).contains(hour),
                  let minute = Int(capture(5)), (0...59).contains(minute), let second = Int(capture(6)), (0...59).contains(second) else { return nil }
            let zone = capture(8)
            var offset = 0
            if zone != "Z" {
                let parts = zone.dropFirst().split(separator: ":")
                guard parts.count == 2, let h = Int(parts[0]), h <= 23, let m = Int(parts[1]), m <= 59 else { return nil }
                offset = (h * 3600 + m * 60) * (zone.first == "-" ? -1 : 1)
            }
            guard let timezone = TimeZone(secondsFromGMT: offset) else { return nil }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timezone
            let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
            guard let date = calendar.date(from: parts) else { return nil }
            let checked = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            guard checked.year == year, checked.month == month, checked.day == day, checked.hour == hour, checked.minute == minute, checked.second == second else { return nil }
            let fraction = capture(7)
            return date.timeIntervalSince1970 * 1000 + (Double("0." + fraction) ?? 0) * 1000
        }
        private func stop(_ parser: XMLParser, _ message: String) {
            if failure == nil { failure = .message(message) }
            parser.abortParsing()
        }
        func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
            stop(parser, "外部参照を含む XML は取り込めません。")
            return nil
        }
        func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { stop(parser, "XML のエンティティ宣言は取り込めません。") }
        func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { stop(parser, "外部参照を含む XML は取り込めません。") }
    }
}
