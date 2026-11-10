import Foundation
import CoreFoundation

/// Additive notebook storage: the original date-keyed page stays in `notes`;
/// additional pages live in `notePages`. Raw dictionaries retain future fields.
struct NativeNotebookPage: Identifiable {
    let id: String
    let day: String
    let value: [String: Any]
}

enum NativeNotebookPages {
    static let contentKeys = ["text", "paper", "font", "layout", "stickers"]
    static let importSourceKey = "_plainwalkImportSourceID"
    static func legacyID(_ day: String) -> String { "legacy:" + day }
    static var blank: [String: Any] { ["text": "", "paper": "plain", "font": "serif", "layout": [[String: Any]](), "stickers": ""] }

    static func list(_ library: [String: Any], day: String? = nil) -> [NativeNotebookPage] {
        let legacy = library["notes"] as? [String: [String: Any]] ?? [:]
        let extra = library["notePages"] as? [String: [String: Any]] ?? [:]
        var result = legacy.compactMap { key, value -> NativeNotebookPage? in
            guard (day == nil || day == key), value["pageDeleted"] as? Bool != true else { return nil }
            return NativeNotebookPage(id: legacyID(key), day: key, value: value)
        }
        result += extra.compactMap { id, value -> NativeNotebookPage? in
            guard let key = value["day"] as? String, day == nil || day == key else { return nil }
            return NativeNotebookPage(id: id, day: key, value: value)
        }
        return result.sorted { a, b in
            if a.id == b.id { return false }
            if a.day != b.day { return a.day > b.day }
            if a.id == legacyID(a.day) { return true }
            if b.id == legacyID(b.day) { return false }
            let ac = nativeNumber(a.value["created"]) ?? 0, bc = nativeNumber(b.value["created"]) ?? 0
            return ac == bc ? a.id < b.id : ac < bc
        }
    }

    static func page(_ library: [String: Any], id: String, day: String) -> NativeNotebookPage? {
        if id == legacyID(day) {
            guard let value = (library["notes"] as? [String: [String: Any]])?[day], value["pageDeleted"] as? Bool != true else { return nil }
            return NativeNotebookPage(id: id, day: day, value: value)
        }
        guard let value = (library["notePages"] as? [String: [String: Any]])?[id], value["day"] as? String == day else { return nil }
        return NativeNotebookPage(id: id, day: day, value: value)
    }

    static func create(day: String) -> NativeNotebookPage {
        let id = UUID().uuidString
        var value = blank; value["id"] = id; value["day"] = day; value["created"] = Date().timeIntervalSince1970 * 1000
        return NativeNotebookPage(id: id, day: day, value: value)
    }

    /// Identity ignores daily steps and normalizes defaults introduced by Web validation.
    static func content(_ raw: [String: Any]) -> [String: Any] {
        var result = raw
        for key in ["id", "day", "steps", "pageDeleted", importSourceKey] { result.removeValue(forKey: key) }
        for (key, value) in blank where result[key] == nil || result[key] is NSNull { result[key] = value }
        return result
    }
    static func equal(_ a: [String: Any], _ b: [String: Any]) -> Bool { jsonEqual(content(a), content(b)) }
    private static func sourceID(_ page: NativeNotebookPage) -> String { page.value[importSourceKey] as? String ?? page.id }
    private static func jsonEqual(_ a: Any, _ b: Any) -> Bool {
        if let a=a as? NSNumber,let b=b as? NSNumber {
            guard (CFGetTypeID(a)==CFBooleanGetTypeID()) == (CFGetTypeID(b)==CFBooleanGetTypeID()) else {return false}
            return a.compare(b) == .orderedSame
        }
        if let a=a as? String,let b=b as? String {return a==b}
        if a is NSNull {return b is NSNull}
        if let a=a as? [Any],let b=b as? [Any] {return a.count==b.count && zip(a,b).allSatisfy {jsonEqual($0.0,$0.1)}}
        if let a=a as? [String:Any],let b=b as? [String:Any] {
            return Set(a.keys)==Set(b.keys) && a.allSatisfy {key,value in b[key].map {jsonEqual(value,$0)} ?? false}
        }
        return false
    }

    /// Optimistic comparison stops an open editor overwriting an import/cutout.
    static func save(_ library: inout [String: Any], page: NativeNotebookPage, expected: [String: Any]?) throws {
        let current = self.page(library, id: page.id, day: page.day)
        if let expected {
            let base = NativeNotebookPage(id: page.id, day: page.day, value: expected)
            guard let current, sourceID(current) == sourceID(base), equal(current.value, expected) else { throw NativeError.message("このページは別の操作で変更または削除されました。下書きは残っています。「別のページとして保存」を選んでください。") }
        } else if current != nil {
            throw NativeError.message("同じページがすでにあります。下書きを別のページとして保存してください。")
        }
        var value = current?.value ?? page.value
        for (key, item) in page.value { value[key] = item }
        value["day"] = page.day
        if page.id == legacyID(page.day) {
            // Preserve daily metadata, including when reopening a deleted first page.
            var notes = library["notes"] as? [String: [String: Any]] ?? [:]
            var merged = notes[page.day] ?? [:]
            for (key, item) in value where key != "steps" { merged[key] = item }
            merged.removeValue(forKey: "pageDeleted"); notes[page.day] = merged; library["notes"] = notes
        } else {
            value["id"] = page.id; value.removeValue(forKey: "pageDeleted")
            var pages = library["notePages"] as? [String: [String: Any]] ?? [:]
            pages[page.id] = value; library["notePages"] = pages
        }
    }

    static func delete(_ library: inout [String: Any], page: NativeNotebookPage) throws {
        guard let current = self.page(library, id: page.id, day: page.day), sourceID(current) == sourceID(page), equal(current.value, page.value) else {
            throw NativeError.message("このページは別の操作で変更または削除されました。もう一度開いて確認してください。")
        }
        if page.id == legacyID(page.day) {
            var notes = library["notes"] as? [String: [String: Any]] ?? [:], value = current.value
            for key in contentKeys { value.removeValue(forKey: key) }
            value["pageDeleted"] = true; notes[page.day] = value; library["notes"] = notes
        } else {
            var pages = library["notePages"] as? [String: [String: Any]] ?? [:]
            pages.removeValue(forKey: page.id); library["notePages"] = pages
        }
    }

    /// A conflicting imported page becomes a copy. Equality is checked before
    /// allocating an ASCII ID, so repeated Web/native imports are idempotent.
    static func merge(_ incoming: [String: Any], into library: inout [String: Any]) {
        let incomingNotes = incoming["notes"] as? [String: [String: Any]] ?? [:]
        var notes = library["notes"] as? [String: [String: Any]] ?? [:]
        for day in incomingNotes.keys.sorted() {
            guard let value = incomingNotes[day] else { continue }
            if notes[day] == nil { notes[day] = value; continue }
            // Steps belong to the day. Unknown keys belong to the page and are
            // retained in a conflicting imported copy rather than changing it.
            if notes[day]?["steps"] == nil, let steps = value["steps"] { notes[day]?["steps"] = steps }
        }
        library["notes"] = notes
        for day in incomingNotes.keys.sorted() {
            guard let value = incomingNotes[day], value["pageDeleted"] as? Bool != true else { continue }
            retainImported(NativeNotebookPage(id: legacyID(day), day: day, value: value), into: &library)
        }
        let extra = incoming["notePages"] as? [String: [String: Any]] ?? [:]
        for id in extra.keys.sorted() {
            guard let value = extra[id], let day = value["day"] as? String else { continue }
            retainImported(NativeNotebookPage(id: id, day: day, value: value), into: &library)
        }
    }

    private static func retainImported(_ incoming: NativeNotebookPage, into library: inout [String: Any]) {
        var pages = library["notePages"] as? [String: [String: Any]] ?? [:]
        var id = incoming.id
        let origin = sourceID(incoming)
        if let current = page(library, id: id, day: incoming.day), sourceID(current) == origin, equal(current.value, incoming.value) { return }
        // A legacy date slot is never replaced, even when it has a tombstone.
        if id.hasPrefix("legacy:") || pages[id] != nil {
            if list(library, day: incoming.day).contains(where: {
                sourceID($0) == origin && equal($0.value, incoming.value)
            }) { return }
            var suffix = 1
            repeat { id = "import:\(incoming.day):\(suffix)"; suffix += 1 } while pages[id] != nil
        }
        var value = incoming.value
        for key in ["steps", "pageDeleted"] { value.removeValue(forKey: key) }
        if id != incoming.id { value[importSourceKey] = origin }
        value["id"] = id; value["day"] = incoming.day; pages[id] = value; library["notePages"] = pages
    }

    #if DEBUG
    static func selfTest() throws -> Bool {
        let day = "2026-11-10"
        guard !equal(["future":true],["future":1]),equal(["future":1.0],["future":1]) else {throw NativeError.message("Notebook equality confused Boolean and numeric metadata.")}
        var library: [String: Any] = ["notes": [day: ["text": "first", "steps": 4321, "future": ["keep": true]]]]
        guard let first = page(library, id: legacyID(day), day: day) else { throw NativeError.message("Legacy notebook identity failed.") }
        var second = create(day: day).value; second["text"] = "second"; second["future"] = 42
        let id = second["id"] as! String
        try save(&library, page: NativeNotebookPage(id: id, day: day, value: second), expected: nil)
        guard list(library, day: day).count == 2 else { throw NativeError.message("Same-day pages were overwritten.") }
        var imported = library
        imported["notes"] = [day: ["text": "conflicting imported page", "steps": 9999, "future": ["keep": true]]]
        merge(imported, into: &library)
        let count = list(library).count
        merge(imported, into: &library)
        guard count == 3, list(library).count == count,
              (library["notes"] as? [String: [String: Any]])?[day]?["steps"] as? Int == 4321 else { throw NativeError.message("Notebook conflict import lost content or daily steps.") }
        // Identical blank pages are still distinct identities. Global content
        // deduplication would silently delete legitimate pages during import.
        let identical: [String:Any] = ["notePages": [
            "blank-a": ["id":"blank-a","day":day],
            "blank-b": ["id":"blank-b","day":day]
        ]]
        var blanks: [String:Any] = ["notes":[String:Any]()]
        merge(identical,into:&blanks);merge(identical,into:&blanks)
        guard list(blanks).count == 2 else {throw NativeError.message("Distinct identical notebook pages were collapsed.")}
        blanks["notePages"] = [
            "blank-a": ["id":"blank-a","day":day,"text":"local a"],
            "blank-b": ["id":"blank-b","day":day,"text":"local b"]
        ]
        merge(identical,into:&blanks);merge(identical,into:&blanks)
        let origins=Set(list(blanks).compactMap {$0.value[importSourceKey] as? String})
        guard list(blanks).count == 4,origins == Set(["blank-a","blank-b"]) else {throw NativeError.message("Notebook conflict origins were collapsed or duplicated.")}
        // Two independent backups can allocate the same intermediate copy ID.
        let collisionID="import:\(day):1"
        var nested: [String:Any] = ["notePages":[collisionID:["id":collisionID,"day":day,importSourceKey:"original-a"]]]
        let other: [String:Any] = ["notePages":[collisionID:["id":collisionID,"day":day,importSourceKey:"original-b"]]]
        merge(other,into:&nested);merge(other,into:&nested)
        guard list(nested).count == 2,Set(list(nested).compactMap {$0.value[importSourceKey] as? String}) == Set(["original-a","original-b"]) else {throw NativeError.message("Nested notebook conflicts lost their original page identity.")}
        let original=page(nested,id:collisionID,day:day)!
        var changed=original.value;changed[importSourceKey]="changed-origin"
        var nestedPages=nested["notePages"] as! [String:[String:Any]];nestedPages[collisionID]=changed;nested["notePages"]=nestedPages
        var rejectedSave=false,rejectedDelete=false
        do {try save(&nested,page:original,expected:original.value)} catch {rejectedSave=true}
        do {try delete(&nested,page:original)} catch {rejectedDelete=true}
        guard rejectedSave,rejectedDelete else {throw NativeError.message("A stale notebook draft overwrote changed import ancestry.")}
        let roundTrip=try JSONSerialization.jsonObject(with:JSONSerialization.data(withJSONObject:library)) as! [String:Any]
        guard (page(roundTrip,id:id,day:day)?.value["future"] as? Int)==42 else {throw NativeError.message("Notebook round trip discarded unknown page fields.")}
        try delete(&library, page: first)
        guard page(library, id: first.id, day: day) == nil, list(library).count == 2,
              ((library["notes"] as? [String: [String: Any]])?[day]?["future"] as? [String: Bool])?["keep"] == true else { throw NativeError.message("Deleting a page removed siblings or unknown metadata.") }
        do { try save(&library, page: first, expected: first.value) } catch { return true }
        throw NativeError.message("A deleted page was silently overwritten by a stale editor.")
    }
    #endif
}
