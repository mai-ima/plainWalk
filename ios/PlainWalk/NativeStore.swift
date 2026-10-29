import Foundation

/// Keeps the existing on-device JSON keys, preserving unrecognized fields for compatible backups.
struct NativeStore {
    let directory: URL
    init(directory: URL? = nil) {
        self.directory=directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("PlainWalk",isDirectory:true)
    }
    func url(_ key: String) -> URL { directory.appendingPathComponent("web-"+key+".json") }
    func read(_ key: String) throws -> [String: Any]? {
        let file=url(key); guard FileManager.default.fileExists(atPath:file.path) else { return nil }
        let bytes=try Data(contentsOf:file)
        let value=try JSONSerialization.jsonObject(with:bytes,options:.fragmentsAllowed)
        if value is NSNull { return nil }
        guard let dict=value as? [String:Any] else { throw NativeError.message("保存データの形式を読み取れません。元のファイルは上書きしません。") }
        return dict
    }
    func write(_ key: String, _ value: [String:Any]?) throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let data=try JSONSerialization.data(withJSONObject:value as Any? ?? NSNull(),options:[.sortedKeys,.fragmentsAllowed])
        try data.write(to:url(key),options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
    }
    static var emptyLibrary: [String:Any] { ["version":1,"walks":[[String:Any]](),"spots":[[String:Any]](),"flags":[[String:Any]](),"notes":[String:Any]()] }
    static func validate(_ library: [String:Any]) throws {
        guard nativeNumber(library["version"])==1, let walks=library["walks"] as? [[String:Any]], let spots=library["spots"] as? [[String:Any]], let flags=library["flags"] as? [[String:Any]], walks.count<=10_000, spots.count<=10_000, flags.count<=10_000 else { throw NativeError.message("このアプリのバックアップではないか、データが大きすぎます。") }
        var seen=Set<String>();var count=0
        for raw in walks { guard let walk=NativeWalk(json:raw), seen.insert(walk.id).inserted else { throw NativeError.message("さんぽの形式または ID が不正です。") };count+=walk.points.count;guard count<=300_000 else {throw NativeError.message("記録点が多すぎます。")}}
        for list in [spots,flags] {
            var seen=Set<String>()
            for item in list {
                guard let id=item["id"] as? String,!id.isEmpty,id.utf16.count<=200,
                      seen.insert(id).inserted,NativePoint(json:item) != nil else {throw NativeError.message("写真ピン・旗の形式が不正です。")}
                for (key, limit, pattern) in [
                    ("photo",5_000_000,"^data:image/(jpeg|png|webp);base64,"),
                    ("video",21_000_000,"^data:video/(mp4|webm|quicktime)(;codecs=[^;,]+)?;base64,")
                ] {
                    guard let value=item[key], !(value is NSNull) else {continue}
                    if let value=value as? String, value.isEmpty {continue}
                    guard let value=value as? String,value.utf16.count<=limit,
                          value.range(of:pattern,options:.regularExpression) != nil else {throw NativeError.message("写真・動画の形式が不正です。")}
                }
            }
        }
        try validateNotes(library["notes"])
        try validateCollections(library)
    }

    private static func validateNotes(_ raw: Any?) throws {
        guard let raw, !(raw is NSNull) else {return}
        guard let notes=raw as? [String:Any], notes.count<=20_000 else {throw NativeError.message("ノートの形式が不正です。")}
        let formatter=DateFormatter()
        formatter.locale=Locale(identifier:"en_US_POSIX");formatter.calendar=Calendar(identifier:.gregorian)
        formatter.timeZone=TimeZone(secondsFromGMT:0);formatter.dateFormat="yyyy-MM-dd";formatter.isLenient=false
        for (day,rawNote) in notes {
            guard day.range(of:"^[0-9]{4}-[0-9]{2}-[0-9]{2}$",options:.regularExpression) != nil,
                  let date=formatter.date(from:day),formatter.string(from:date)==day,
                  let note=rawNote as? [String:Any] else {throw NativeError.message("ノートの日付が不正です。")}
            guard (note["text"] as? String ?? "").utf16.count<=5_000,
                  (note["stickers"] as? String ?? "").utf16.count<=1_000 else {throw NativeError.message("ノートの文字数が大きすぎます。")}
            let rawLayout: Any = note["layout"] is NSNull ? [[String:Any]]() : (note["layout"] ?? [[String:Any]]())
            guard let layout=rawLayout as? [[String:Any]],layout.count<=20 else {throw NativeError.message("ノートの素材が多すぎます。")}
            for item in layout {
                guard item["id"] is String,let kind=item["type"] as? String,["photo","sticker","route","emoji"].contains(kind),
                      nativeNumber(item["x"]) != nil,nativeNumber(item["y"]) != nil,
                      let width=nativeNumber(item["width"]),(10...1_000).contains(width),
                      let ratio=nativeNumber(item["ratio"]),(0.01...100).contains(ratio) else {throw NativeError.message("ノートの配置が不正です。")}
                if let rotation=item["rotation"],nativeNumber(rotation)==nil {throw NativeError.message("ノートの角度が不正です。")}
                if kind != "emoji" {
                    guard let image=item["src"] as? String,image.utf16.count<=5_000_000,
                          image.range(of:"^data:image/(jpeg|png|webp);base64,",options:.regularExpression) != nil else {throw NativeError.message("ノートの画像が不正です。")}
                }
            }
            if let rawSteps=note["steps"] {
                guard let steps=nativeNumber(rawSteps),steps.rounded(.towardZero)==steps,(0...100_000).contains(steps) else {throw NativeError.message("歩数の形式が不正です。")}
            }
        }
    }

    private static func validateCollections(_ library: [String:Any]) throws {
        var totalPoints=0
        func checkPoints(_ raw: Any?) throws {
            guard let points=raw as? [[String:Any]],points.count<=300_000,
                  points.allSatisfy({NativePoint(json:$0) != nil}) else {throw NativeError.message("コレクションの位置情報が不正です。")}
            totalPoints+=points.count
            guard totalPoints<=300_000 else {throw NativeError.message("コレクションの位置情報が多すぎます。")}
        }
        for key in ["bookmarks","doodles","sharedMaps"] {
            guard let raw=library[key] else {continue}
            guard let items=raw as? [[String:Any]],items.count<=1_000 else {throw NativeError.message("コレクションが大きすぎます。")}
            var seen=Set<String>()
            for item in items {
                guard let id=item["id"] as? String,!id.isEmpty,id.utf16.count<=200,seen.insert(id).inserted,
                      let name=item["name"] as? String,name.utf16.count<=200 else {throw NativeError.message("コレクションの形式または ID が不正です。")}
                switch key {
                case "bookmarks":
                    guard NativePoint(json:item) != nil else {throw NativeError.message("しおりの位置が不正です。")}
                case "doodles":
                    guard nativeTime(item["created"]) != nil else {throw NativeError.message("らくがきの日付が不正です。")}
                    try checkPoints(item["points"])
                default:
                    guard let walks=item["walks"] as? [[String:Any]],walks.count<=10_000 else {throw NativeError.message("共有の道が多すぎます。")}
                    for walk in walks {
                        guard walk["id"] is String else {throw NativeError.message("共有の道が不正です。")}
                        try checkPoints(walk["points"])
                    }
                }
            }
        }
    }
    #if DEBUG
    static func selfTest() throws -> Bool {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("native-store-"+UUID().uuidString,isDirectory:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        let store=NativeStore(directory:folder);var library=emptyLibrary
        library["unknownFutureField"]=["preserved":true];library["notes"]=["2026-10-29":["text":"test","futureNoteValue":42]]
        try store.write("library",library);let restored=try store.read("library")!
        try validate(restored)
        guard (restored["unknownFutureField"] as? [String:Bool])?["preserved"]==true,((restored["notes"] as? [String:Any])?["2026-10-29"] as? [String:Any])?["futureNoteValue"] as? Int==42 else {throw NativeError.message("Unknown data was not preserved.")}
        let goodWalk: [String:Any] = ["id":"walk","start":1_000.0,"end":2_000.0,"duration":1_000.0,"points":[["lat":35.0,"lon":139.0,"t":1_000.0],["lat":35.0001,"lon":139.0,"t":2_000.0]]]
        var valid=emptyLibrary;valid["walks"]=[goodWalk]
        try validate(valid)
        guard NativeWalk(json:goodWalk)?.duration==1 else {throw NativeError.message("Milliseconds were not converted to seconds.")}
        func mustReject(_ value: [String:Any]) throws {
            do {try validate(value)} catch {return}
            throw NativeError.message("Invalid backup passed native validation.")
        }
        for field in ["start","end","duration"] {
            var walk=goodWalk
            walk[field] = field=="end" ? 0.0 : field=="duration" ? -1.0 : 9_000_000_000_000_000.0
            var invalid=emptyLibrary;invalid["walks"]=[walk];try mustReject(invalid)
        }
        var noTime=goodWalk;noTime["points"]=[["lat":35.0,"lon":139.0]]
        var invalid=emptyLibrary;invalid["walks"]=[noTime];try mustReject(invalid)
        var jump=goodWalk;jump["points"]=[["lat":35.0,"lon":139.0,"t":1_000.0],["lat":36.0,"lon":139.0,"t":2_000.0]]
        invalid["walks"]=[jump];try mustReject(invalid)
        jump["points"]=[["lat":35.0,"lon":139.0,"t":1_000.0],["lat":36.0,"lon":139.0,"t":2_000.0,"break":true]]
        valid["walks"]=[jump];try validate(valid)
        invalid=emptyLibrary;invalid["notes"]=["2026-02-30":["text":"invalid date"]];try mustReject(invalid)
        invalid=emptyLibrary;invalid["doodles"]=[["id":"doodle","name":"invalid","created":1_000.0,"points":[["lat":200.0,"lon":139.0]]]];try mustReject(invalid)
        return true
    }
    #endif
}
