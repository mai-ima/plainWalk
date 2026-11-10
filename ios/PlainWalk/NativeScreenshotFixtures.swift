#if DEBUG
import Foundation
import UIKit

/// Explicit screenshot-only data. Every launch gets a new temporary store;
/// the real Application Support library is never read, replaced, or deleted.
@MainActor enum NativeScreenshotFixtures {
    static let walkID = "screen-walk-today"
    static let previousWalkID = "screen-walk-yesterday"
    static let spotID = "screen-spot"
    static let bookmarkID = "screen-bookmark"
    static let doodleID = "screen-doodle"
    static let sharedMapID = "screen-shared-map"
    static let photoItemID = "screen-note-photo"
    static let stickerID = "screen-note-sticker"
    static let routeItemID = "screen-note-route"
    static let emojiItemID = "screen-note-emoji"
    private static let referenceDate = Date()
    private static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = .current
        return value
    }
    static var day: Date { calendar.startOfDay(for: referenceDate) }
    static var dayKey: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: day)
    }
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-PlainWalkScreenshotFixture")
    }

    static func makeModel() -> NativeAppModel {
        guard isEnabled else { return NativeAppModel() }
        do {
            // Keep the directory for the model's lifetime. The OS may reclaim
            // these temporary fixture folders; no broad cleanup touches user data.
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("PlainWalk-ScreenshotFixture-" + UUID().uuidString, isDirectory: true)
            let store = NativeStore(directory: directory)
            let library = try makeLibrary()
            try NativeStore.validate(library)
            try store.write("library", library)
            try store.write("config", [
                "dark": "light", "theme": 0, "line": "solid", "pin": "badge",
                "locationMark": "dot", "showPhotos": true, "showTweets": true,
                "highlight": true, "thicken": true, "smooth": true,
                "fadeOther": true, "outline": false, "grid": false,
                "beta": true, "developerMode": true, "units": "km",
                "healthEnabled": false, "wake": false
            ])
            let model = NativeAppModel(store: store, runtimeServicesEnabled: false)
            guard model.errorMessage == nil, model.walks.count == 2,
                  model.spots.count == 1, model.flags.count == 1 else {
                throw NativeError.message("Screenshot fixture did not load intact.")
            }
            return model
        } catch {
            NSLog("PlainWalk synthetic screenshot fixture failed: %@", error.localizedDescription)
            fatalError("Synthetic screenshot fixture failed: " + error.localizedDescription)
        }
    }

    private static func makeLibrary() throws -> [String: Any] {
        let photo = try illustration(sticker: false)
        let sticker = try illustration(sticker: true)
        let route = try routeImage()
        let todayStart = calendar.date(bySettingHour: 8, minute: 15, second: 0, of: day) ?? day
        let priorDay = calendar.date(byAdding: .day, value: -1, to: day) ?? day.addingTimeInterval(-86_400)
        let priorStart = calendar.date(bySettingHour: 10, minute: 10, second: 0, of: priorDay) ?? priorDay
        let today = points(start: todayStart, north: 0, east: 0, includeGap: true)
        let previous = points(start: priorStart, north: 0.0008, east: -0.0015, includeGap: false)
        func walk(_ id: String, _ name: String, _ values: [NativePoint]) -> [String: Any] {
            ["id": id, "name": name, "start": values.first!.t, "end": values.last!.t,
             "duration": values.last!.t - values.first!.t, "points": values.map(\.json),
             "steps": 1360, "note": "検証用の合成データです。実際の歩行・撮影・位置測定の記録ではありません。"]
        }
        var spot = today[12].json
        spot.merge(["id": spotID, "text": "検証用イラスト：駅の近くの緑", "emoji": "♡", "photo": photo]) { _, new in new }
        var bookmark = today[28].json
        bookmark.merge(["id": bookmarkID, "name": "検証用：東京駅の近く", "created": today[28].t]) { _, new in new }
        var flag = today[30].json
        flag.merge(["id": "screen-flag", "name": "検証用の目的地"]) { _, new in new }
        let doodlePoints = Array(today[3...18]).enumerated().map { index, point -> [String: Any] in
            var value = point.json
            value["break"] = index == 0
            if index < 3 { value["done"] = true }
            return value
        }
        // Shared maps intentionally contain geometry only, as normal exports do.
        func sharedWalk(_ id: String, _ values: [NativePoint]) -> [String: Any] {
            ["id": id, "points": values.map { point -> [String: Any] in
                var value: [String: Any] = ["lat": point.lat, "lon": point.lon]
                if point.isBreak { value["break"] = true }
                return value
            }]
        }
        let layout: [[String: Any]] = [
            ["id": photoItemID, "type": "photo", "src": photo, "x": 350.0, "y": 340.0,
             "width": 450.0, "ratio": 4.0 / 3.0, "rotation": -4.0, "opacity": 1.0],
            ["id": routeItemID, "type": "route", "src": route, "x": 325.0, "y": 725.0,
             "width": 375.0, "ratio": 1.5, "rotation": 2.0, "opacity": 0.9],
            ["id": stickerID, "type": "sticker", "src": sticker, "x": 560.0, "y": 580.0,
             "width": 170.0, "ratio": 1.0, "rotation": 12.0, "finish": "plain"],
            ["id": emojiItemID, "type": "emoji", "text": "✦", "x": 145.0, "y": 565.0,
             "width": 75.0, "ratio": 1.0, "rotation": -8.0]
        ]
        var library = NativeStore.emptyLibrary
        library["walks"] = [walk(walkID, "検証用：駅のまわり", today), walk(previousWalkID, "検証用：前日のさんぽ", previous)]
        library["spots"] = [spot]
        library["flags"] = [flag]
        library["bookmarks"] = [bookmark]
        library["doodles"] = [["id": doodleID, "name": "検証用：小さな曲線", "created": today[3].t, "points": doodlePoints]]
        library["sharedMaps"] = [["id": sharedMapID, "name": "検証用の共有白地図", "walks": [sharedWalk(walkID, today), sharedWalk(previousWalkID, previous)]]]
        library["notes"] = [dayKey: [
            "day": dayKey, "text": "検証用のノート\n写真・道・ステッカーの配置を確認します。",
            "paper": "grid", "font": "serif", "layout": layout, "stickers": "", "steps": 1360
        ]]
        library["notePages"] = ["screen-note-second": [
            "id": "screen-note-second", "day": dayKey,
            "text": "同じ日の2枚目\nページごとに内容を保存します。",
            "paper": "lined", "font": "sans", "layout": [[String: Any]](), "stickers": "🌿"
        ]]
        return library
    }

    private static func points(start: Date, north: Double, east: Double, includeGap: Bool) -> [NativePoint] {
        // Public Tokyo Station vicinity, mathematically generated; never user GPS.
        (0..<40).map { index in
            let angle = Double(index) / 39 * 2 * Double.pi
            return NativePoint(lat: 35.681236 + north + 0.0023 * sin(angle),
                               lon: 139.767125 + east + 0.003 * cos(angle),
                               t: start.timeIntervalSince1970 * 1000 + Double(index) * 30_000,
                               accuracy: 5, isBreak: index == 0 || (includeGap && index == 22),
                               mode: "walking")
        }
    }

    private static func illustration(sticker: Bool) throws -> String {
        let size = sticker ? CGSize(width: 320, height: 320) : CGSize(width: 640, height: 480)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = !sticker
        let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            if !sticker {
                UIColor(red: 0.88, green: 0.94, blue: 0.97, alpha: 1).setFill()
                renderer.fill(CGRect(origin: .zero, size: size))
                UIColor(red: 0.78, green: 0.87, blue: 0.74, alpha: 1).setFill()
                renderer.fill(CGRect(x: 0, y: 275, width: 640, height: 205))
                UIColor.white.withAlphaComponent(0.7).setFill()
                UIBezierPath(ovalIn: CGRect(x: 60, y: 60, width: 175, height: 58)).fill()
            }
            let offset = sticker ? CGPoint(x: 16, y: 10) : CGPoint(x: 180, y: 100)
            UIColor(red: 0.42, green: 0.32, blue: 0.22, alpha: 1).setFill()
            renderer.fill(CGRect(x: offset.x + 130, y: offset.y + 100, width: 30, height: 150))
            UIColor(red: 0.24, green: 0.47, blue: 0.31, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: offset.x + 42, y: offset.y + 20, width: 205, height: 160)).fill()
            UIBezierPath(ovalIn: CGRect(x: offset.x + 80, y: offset.y, width: 150, height: 155)).fill()
            let label = sticker ? "検証用" : "検証用の合成イラスト"
            (label as NSString).draw(at: CGPoint(x: 24, y: size.height - 42), withAttributes: [
                .font: UIFont.systemFont(ofSize: sticker ? 18 : 22, weight: .medium),
                .foregroundColor: UIColor(red: 0.16, green: 0.24, blue: 0.19, alpha: 1)
            ])
        }
        guard let data = image.pngData() else { throw NativeError.message("Could not create screenshot illustration.") }
        return "data:image/png;base64," + data.base64EncodedString()
    }

    private static func routeImage() throws -> String {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 450, height: 300), format: format).image { _ in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 50, y: 245))
            path.addCurve(to: CGPoint(x: 360, y: 195), controlPoint1: CGPoint(x: 370, y: 20), controlPoint2: CGPoint(x: 75, y: 35))
            path.addLine(to: CGPoint(x: 290, y: 265))
            UIColor(red: 0.2, green: 0.26, blue: 0.22, alpha: 1).setStroke()
            path.lineWidth = 4; path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke()
            ("検証用の道" as NSString).draw(at: CGPoint(x: 20, y: 12), withAttributes: [
                .font: UIFont.systemFont(ofSize: 18), .foregroundColor: UIColor.darkGray
            ])
        }
        guard let data = image.pngData() else { throw NativeError.message("Could not create screenshot route.") }
        return "data:image/png;base64," + data.base64EncodedString()
    }
}
#endif
