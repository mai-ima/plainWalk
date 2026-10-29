import Foundation
import CoreFoundation
import SwiftUI

func nativeNumber(_ value: Any?) -> Double? {
    guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
    return value.doubleValue
}
func nativeTime(_ value: Any?) -> Double? {
    guard let value = nativeNumber(value), abs(value) <= 8_640_000_000_000_000 else { return nil }
    return value
}
struct NativePoint: Equatable {
    var lat: Double
    var lon: Double
    var t: Double
    var accuracy: Double?
    var isBreak: Bool
    var mode: String
    var heading: Double?
    init(lat: Double, lon: Double, t: Double = Date().timeIntervalSince1970 * 1000, accuracy: Double? = nil, isBreak: Bool = false, mode: String = "walking", heading: Double? = nil) {
        self.lat=lat; self.lon=lon; self.t=t; self.accuracy=accuracy; self.isBreak=isBreak; self.mode=mode
        self.heading = heading.flatMap { $0.isFinite && $0 >= 0 ? $0.truncatingRemainder(dividingBy: 360) : nil }
    }
    init?(json: [String: Any]) {
        guard let lat=nativeNumber(json["lat"]), let lon=nativeNumber(json["lon"]), abs(lat)<=85, abs(lon)<=180 else { return nil }
        self.init(lat:lat,lon:lon,t:nativeNumber(json["t"]) ?? 0,accuracy:nativeNumber(json["accuracy"]),isBreak:json["break"] as? Bool ?? json["gap"] as? Bool ?? false,mode:json["mode"] as? String ?? "walking",heading:nativeNumber(json["heading"]))
    }
    init(_ recorded: RecordedPoint) { self.init(lat:recorded.lat,lon:recorded.lon,t:recorded.t,accuracy:recorded.accuracy,isBreak:recorded.gap,mode:recorded.mode ?? "walking",heading:recorded.heading) }
    var json: [String: Any] {
        var value: [String: Any] = ["lat":lat,"lon":lon,"t":t,"break":isBreak,"mode":mode]
        if let accuracy { value["accuracy"]=accuracy }; if let heading { value["heading"]=heading }; return value
    }
}
struct NativeWalk: Identifiable {
    let id: String
    let name: String
    let start: Double
    let end: Double
    let points: [NativePoint]
    var pioneered: Double
    let note: String
    let raw: [String: Any]
    init?(json: [String: Any], pioneered: Double = 0) {
        guard let id=json["id"] as? String, !id.isEmpty, id.utf16.count <= 200,
              let start=nativeTime(json["start"]), let end=nativeTime(json["end"]), end >= start,
              let rawPoints=json["points"] as? [[String: Any]], rawPoints.count<=300_000,
              rawPoints.allSatisfy({ nativeTime($0["t"]) != nil }) else { return nil }
        if let rawDuration = json["duration"] {
            guard let duration = nativeNumber(rawDuration), duration >= 0 else { return nil }
        }
        let points=rawPoints.compactMap(NativePoint.init(json:)); guard points.count==rawPoints.count else { return nil }
        for index in points.indices.dropFirst() where !points[index].isBreak {
            guard NativeTrackMath.distance(points[index - 1], points[index]) <= 50_000 else { return nil }
        }
        self.id=id; self.name=json["name"] as? String ?? "さんぽ"; self.start=start; self.end=end; self.points=points; self.pioneered=pioneered; self.note=json["note"] as? String ?? ""; self.raw=json
    }
    var distance: Double { NativeTrackMath.trailDistance(points) }
    var duration: TimeInterval { max(0, (nativeNumber(raw["duration"]) ?? (end-start))/1000) }
}
struct NativeSpot: Identifiable {
    let id: String
    let text: String
    let emoji: String
    let point: NativePoint
    let photoData: Data?
    let raw: [String: Any]
    init?(json: [String: Any]) {
        guard let id=json["id"] as? String, let point=NativePoint(json:json) else { return nil }
        self.id=id; self.point=point; self.text=json["text"] as? String ?? ""; self.emoji=json["emoji"] as? String ?? "♡"; self.raw=json
        if let value=json["photo"] as? String, value.hasPrefix("data:image/"), let separator=value.firstIndex(of:",") { self.photoData=Data(base64Encoded:String(value[value.index(after:separator)...])) } else { self.photoData=nil }
    }
}
struct NativeFlag: Identifiable {
    let id: String
    let name: String
    let point: NativePoint
    init(id: String, name: String, point: NativePoint) { self.id=id; self.name=name; self.point=point }
    init?(json: [String: Any]) {
        guard let id=json["id"] as? String, let point=NativePoint(json:json) else { return nil }
        self.init(id:id,name:json["name"] as? String ?? "目的地",point:point)
    }
    var json: [String: Any] { var value=point.json;value["id"]=id;value["name"]=name;return value }
}
enum NativeTab: Hashable { case map, records, profile }
enum NativeCollection: String, Identifiable, CaseIterable {
    case spots, stickers, badges, doodles, sharedMaps, bookmarks, notes
    var id: String { rawValue }
    var title: String { switch self { case .spots:return "ここいいな";case .stickers:return "ステッカー";case .badges:return "エリアバッジ";case .doodles:return "らくがき";case .sharedMaps:return "共有の白地図";case .bookmarks:return "気になる場所";case .notes:return "ノート" } }
}
enum NativeSheet: Identifiable {
    case settings, developer, layers, menu, spot, answer, stats, replay(String?), walk(String), collection(NativeCollection), share(URL), health
    var id: String { switch self {case .settings:return "settings";case .developer:return "developer";case .layers:return "layers";case .menu:return "menu";case .spot:return "spot";case .answer:return "answer";case .stats:return "stats";case .replay(let id):return "replay:"+(id ?? "all");case .walk(let id):return "walk:"+id;case .collection(let item):return "collection:"+item.rawValue;case .share(let url):return "share:"+url.absoluteString;case .health:return "health"} }
}
