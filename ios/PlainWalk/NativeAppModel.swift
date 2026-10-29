import SwiftUI
import CoreLocation
import Combine
import UniformTypeIdentifiers

// The detached importer constructs fresh, immutable JSON value trees before
// handing them to the main actor. No mutable Foundation object is shared.
private struct NativeImportPayload: @unchecked Sendable {
    var library: [String:Any]?
    var sharedMap: [String:Any]?
    var walks: [[String:Any]] = []
}

@MainActor final class NativeAppModel: ObservableObject {
    @Published var tab: NativeTab = .map
    @Published var sheet: NativeSheet?
    @Published var errorMessage: String?
    @Published var importing = false
    @Published private(set) var library = NativeStore.emptyLibrary
    @Published private(set) var config: [String:Any] = [:]
    @Published private(set) var walks: [NativeWalk] = []
    @Published private(set) var spots: [NativeSpot] = []
    @Published private(set) var flags: [NativeFlag] = []
    @Published private(set) var currentPoint: NativePoint?
    @Published private(set) var accuracy = 0.0
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var activePoints: [NativePoint] = []
    @Published private(set) var todaySteps: Double?
    @Published private(set) var todayPioneered = 0.0
    @Published private(set) var totalPioneered = 0.0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var recordingDistance = 0.0
    @Published private(set) var libraryRevision = 0
    @Published private(set) var mapFocus: NativePoint?
    @Published private(set) var mapFocusRevision = 0
    @Published private(set) var focusedWalkID: String?
    let recorder: LocationRecorder
    private let store: NativeStore
    private let runtimeServicesEnabled: Bool
    private let activity = LiveActivityService()
    private var active: [String:Any]?
    private var readFailure = false
    private var activeReadFailure = false
    private let doodleProgress = NativeDoodleProgress()
    private var explored = Set<String>()
    private var activeExplored = Set<String>()
    private var activePioneered = 0.0
    private var activeTodayPioneered = 0.0
    private var recorderDistanceOffset = 0.0
    private var stepRefreshRevision = 0
    private var lastStepRefresh = Date()
    private var queuedSheet: NativeSheet?
    private var afterDismiss: (() -> Void)?
    private var clock: AnyCancellable?
    private var savedToday = 0.0
    private var savedTotal = 0.0
    private var pioneeredByDay: [Date:Double] = [:]
    private var lastDay = Calendar.current.startOfDay(for:Date())
    var distanceUnit: String { config["units"] as? String == "mi" ? "mi" : "km" }
    private var palette: NativeLayerPalette { let index=Int(min(Double(NativeLayerPalette.all.count-1),max(0,nativeNumber(config["theme"]) ?? 0)));return NativeLayerPalette.all[index] }
    var paper: Color {
        let light = UIColor(palette.paper)
        let forcedDark = colorScheme.map { $0 == .dark }
        return Color(uiColor: UIColor { traits in
            (forcedDark ?? (traits.userInterfaceStyle == .dark))
                ? UIColor(red: 0.07, green: 0.08, blue: 0.075, alpha: 1) : light
        })
    }
    var ink: Color {
        let light = UIColor(palette.ink)
        let forcedDark = colorScheme.map { $0 == .dark }
        return Color(uiColor: UIColor { traits in
            (forcedDark ?? (traits.userInterfaceStyle == .dark)) ? .white : light
        })
    }
    var colorScheme: ColorScheme? { switch config["dark"] as? String {case "dark":return .dark;case "light":return .light;default:return nil} }
    init(store: NativeStore = NativeStore(), recorder recordingSource: LocationRecorder? = nil, runtimeServicesEnabled: Bool = true) {
        self.store = store
        self.recorder = recordingSource ?? LocationRecorder(storageDirectory: store.directory)
        self.runtimeServicesEnabled = runtimeServicesEnabled
        do { let saved=try store.read("library") ?? NativeStore.emptyLibrary;try NativeStore.validate(saved);library=saved }
        catch { readFailure=true;errorMessage="保存データを読み取れません。元のファイルを残しています。バックアップを書き出すか、正常なバックアップを取り込んでください。\n"+error.localizedDescription }
        do { config=try store.read("config") ?? [:] } catch { errorMessage=error.localizedDescription }
        do { active=try store.read("active");if let active {try validateActive(active)} } catch {activeReadFailure=true;active=nil;errorMessage="中断した記録を読み取れません。元のファイルを残しています。\n"+error.localizedDescription}
        rebuildLibrary()
        if let session=recorder.session {
            if let previous=active,previous["id"] as? String != session.id {
                do {try store.write("active-recovery-"+UUID().uuidString,previous)} catch {activeReadFailure=true;showError("別の中断記録の控えを保存できません。\n"+error.localizedDescription)}
            }
            if active?["id"] as? String != session.id {active=["id":session.id,"start":session.start,"name":"さんぽ","pausedMs":0]}
            var pointsByTime=[Double:NativePoint]()
            for raw in active?["points"] as? [[String:Any]] ?? [] {if let point=NativePoint(json:raw){pointsByTime[point.t]=point}}
            for raw in session.points {let point=NativePoint(raw);pointsByTime[point.t]=point}
            activePoints=pointsByTime.values.sorted{$0.t<$1.t}
            active?["pauseAt"]=nativeTime(active?["pauseAt"]) ?? activePoints.last?.t ?? session.start
            isPaused=true;recordingDistance=NativeTrackMath.trailDistance(activePoints);recorderDistanceOffset=max(0,recordingDistance-session.distance)
        } else if let raw=active {
            activePoints=(raw["points"] as? [[String:Any]] ?? []).compactMap(NativePoint.init(json:));isPaused=true
            active?["pauseAt"]=nativeTime(raw["pauseAt"]) ?? nativeTime(raw["checkpointAt"]) ?? activePoints.last?.t ?? nativeTime(raw["start"]) ?? Date().timeIntervalSince1970*1000
            recordingDistance=NativeTrackMath.trailDistance(activePoints)
        }
        if let id=active?["id"] as? String,walks.contains(where:{$0.id==id}) {do{try clearFinalizedRecording()}catch{showError("さんぽは保存済みです。中断記録の後片付けを再試行してください。\n"+error.localizedDescription)}}
        rebuildActiveExploration()
        recorder.onError={ [weak self] in self?.showError($0) }
        recorder.onHeading = { [weak self] heading in self?.currentPoint?.heading = heading }
        recorder.onPoint={ [weak self] point,id in self?.receive(point,id:id) }
        recorder.onSession={ [weak self] session in
            guard let self else{return};let wasRecording=self.isRecording;self.isRecording=session?.recording ?? false;self.isPaused=self.active != nil && !self.isRecording;if let session{self.recordingDistance=session.distance+self.recorderDistanceOffset};if self.runtimeServicesEnabled{self.activity.update(session)}
            if wasRecording && !self.isRecording && self.active != nil && self.active?["pauseAt"] == nil {self.active?["pauseAt"]=Date().timeIntervalSince1970*1000;do{try self.persistActive()}catch{self.showError(error.localizedDescription)}}
            if self.runtimeServicesEnabled {UIApplication.shared.isIdleTimerDisabled=self.isRecording && self.config["wake"] as? Bool == true}
        }
        if let issue=recorder.recoveryIssue {showError(issue)}
        if runtimeServicesEnabled {
            clock=Timer.publish(every:1,on:.main,in:.common).autoconnect().sink { [weak self] _ in
                guard UIApplication.shared.applicationState != .background else {return}
                self?.tick()
            }
        }
        tick()
    }
    func haptic() { if runtimeServicesEnabled { UIImpactFeedbackGenerator(style:.light).impactOccurred() } }
    func distanceText(_ meters:Double)->String { String(format:"%.2f",meters.isFinite ? max(0,meters)/(distanceUnit=="mi" ? 1609.344 : 1000) : 0) }
    func showError(_ value:String) {errorMessage=value}
    func present(_ value:NativeSheet) {if sheet != nil {queuedSheet=value;sheet=nil}else{sheet=value}}
    func closeSheet() {sheet=nil}
    func sheetDismissed() {if let value=queuedSheet {queuedSheet=nil;sheet=value};if let action=afterDismiss {afterDismiss=nil;action()}}
    private func afterClosing(_ action:@escaping()->Void) {if sheet != nil {afterDismiss=action;sheet=nil}else{action()}}
    func openAnswerMap(){present(.answer)}
    func openLayers(){present(.layers)}
    func openMenu(){present(.menu)}
    func openSettings(){present(.settings)}
    func openWalk(_ id:String){present(.walk(id))}
    func openStats(){present(.stats)}
    func openReplay(){present(.replay(nil))}
    func openReplay(walkID:String){present(.replay(walkID))}
    func openCollection(_ item:NativeCollection){present(.collection(item))}
    func openSpotCapture(){guard isRecording,currentPoint != nil else{showError("記録中に位置情報を取得してから、ここいいなを残せます。");return};present(.spot)}
    func showWalkOnMap(id:String){focusedWalkID=id;mapFocus=walks.first(where:{$0.id==id})?.points.first;mapFocusRevision+=1;tab = .map;closeSheet()}
    func navigateToFlag(_ flag:NativeFlag){mapFocus=flag.point;focusedWalkID=nil;mapFocusRevision+=1;tab = .map;closeSheet()}
    func locate(){do{try recorder.start(id:nil,start:nil,recording:false)}catch{showError(error.localizedDescription)}}
    func updateConfig(key:String,value:Any){var next=config;next[key]=value;saveConfig(next)}
    func saveConfig(_ next:[String:Any]) {do{try store.write("config",next);config=next;UIApplication.shared.isIdleTimerDisabled=isRecording && next["wake"] as? Bool == true}catch{showError(error.localizedDescription)}}
    private func validateActive(_ value:[String:Any]) throws {
        guard let id=value["id"] as? String,!id.isEmpty,id.utf16.count<=200,let start=nativeTime(value["start"]),
              let points=value["points"] as? [[String:Any]],points.count<=300_000 else {throw NativeError.message("中断記録の形式が不正です。")}
        if let raw=value["pausedMs"] {guard let pause=nativeNumber(raw),pause>=0 else{throw NativeError.message("一時停止時間が不正です。")}}
        if let raw=value["pauseAt"] {guard let pause=nativeTime(raw),pause>=start else{throw NativeError.message("一時停止時刻が不正です。")}}
        var previous:NativePoint?
        for raw in points {
            guard nativeTime(raw["t"]) != nil,let point=NativePoint(json:raw),point.t>=start else {throw NativeError.message("中断記録の位置情報が不正です。")}
            if let previous {guard point.t>previous.t,point.isBreak || NativeTrackMath.distance(previous,point)<=50_000 else{throw NativeError.message("中断記録の順序が不正です。")}}
            previous=point
        }
    }
    private var activeWasSaved:Bool {guard let id=active?["id"] as? String else{return false};return walks.contains{$0.id==id}}
    private func clearFinalizedRecording() throws {
        try recorder.stop(end:true)
        try store.write("active",nil)
        active=nil;activeReadFailure=false;activePoints=[];activeExplored=[];activePioneered=0;activeTodayPioneered=0;recorderDistanceOffset=0
        isRecording=false;isPaused=false;recordingDistance=0;elapsed=0;refreshTotals()
    }
    private func adoptActiveIfNeeded() throws {
        guard recorder.session==nil,let active,let id=active["id"] as? String,let start=nativeTime(active["start"]) else{return}
        let points=activePoints.enumerated().map { index,point in
            RecordedPoint(lat:point.lat,lon:point.lon,t:point.t,accuracy:point.accuracy ?? 0,seq:index+1,gap:point.isBreak,mode:point.mode,heading:point.heading)
        }
        try recorder.adoptRecoveredSession(id:id,start:start,points:points)
        recorderDistanceOffset=0
    }
    func updateLibrary(_ change:(inout [String:Any])->Void) throws {
        guard !readFailure else{throw NativeError.message("元の保存ファイルを保護しています。正常なバックアップを取り込んでください。")}
        var next=library;change(&next);try NativeStore.validate(next);try store.write("library",next);library=next;rebuildLibrary()
    }
    private func rebuildLibrary(){
        var values=(library["walks"] as? [[String:Any]] ?? []).compactMap{NativeWalk(json:$0)}
        let totals=NativeTrackMath.exploration(values);for i in values.indices{values[i].pioneered=totals[values[i].id] ?? 0};walks=values.sorted{$0.start>$1.start}
        spots=(library["spots"] as? [[String:Any]] ?? []).compactMap(NativeSpot.init(json:));flags=(library["flags"] as? [[String:Any]] ?? []).compactMap(NativeFlag.init(json:))
        explored = []
        pioneeredByDay = [:]
        for walk in values.sorted(by: { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }) where walk.points.count > 1 {
            for index in 1..<walk.points.count where !walk.points[index].isBreak {
                let before = walk.points[index - 1], point = walk.points[index]
                let keys = NativeTrackMath.cellKeys(before, point)
                guard !keys.isEmpty else { continue }
                let fresh = keys.filter { !explored.contains($0) }.count
                let contribution = NativeTrackMath.distance(before, point) * Double(fresh) / Double(keys.count)
                let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: point.t / 1000))
                pioneeredByDay[day, default: 0] += contribution
                explored.formUnion(keys)
            }
        }
        refreshTotals();libraryRevision+=1
    }
    private func refreshTotals() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        savedTotal = walks.reduce(0) { $0 + $1.pioneered }
        savedToday = pioneeredByDay[day] ?? 0
        totalPioneered = savedTotal + activePioneered
        todayPioneered = savedToday + activeTodayPioneered
    }
    private func rebuildActiveExploration() {
        activeExplored = []
        activePioneered = 0
        activeTodayPioneered = 0
        if !activeWasSaved && activePoints.count > 1 {
            for index in 1..<activePoints.count { appendExploration(activePoints[index - 1], activePoints[index]) }
        }
        refreshTotals()
    }
    private func appendExploration(_ a: NativePoint, _ b: NativePoint) {
        guard !b.isBreak else { return }
        let keys = NativeTrackMath.cellKeys(a, b)
        guard !keys.isEmpty else { return }
        let fresh = keys.filter { !explored.contains($0) && !activeExplored.contains($0) }.count
        let contribution = NativeTrackMath.distance(a, b) * Double(fresh) / Double(keys.count)
        activePioneered += contribution
        if Calendar.current.isDateInToday(Date(timeIntervalSince1970: b.t / 1000)) {
            activeTodayPioneered += contribution
        }
        activeExplored.formUnion(keys)
    }
    private func receive(_ value:RecordedPoint,id:String?){let point=NativePoint(value);currentPoint=point;accuracy=value.accuracy;guard let id,id==active?["id"] as? String,!activeWasSaved else{return};if let last=activePoints.last {guard point.t>last.t else{return};appendExploration(last,point)};activePoints.append(point);recordingDistance=(recorder.session?.distance ?? 0)+recorderDistanceOffset;totalPioneered=savedTotal+activePioneered;todayPioneered=savedToday+activeTodayPioneered
        let completions=doodleProgress.completedPoints(in:library["doodles"] as? [[String:Any]] ?? [],at:point,revision:libraryRevision)
        if !completions.isEmpty {do{try updateLibrary{data in data["doodles"]=NativeDoodleProgress.applying(completions,to:data["doodles"] as? [[String:Any]] ?? [])};doodleProgress.didApply(revision:libraryRevision)}catch{showError(error.localizedDescription)}}
    }
    private func persistActive() throws {guard var value=active else{try store.write("active",nil);return};value["points"]=activePoints.map(\.json);try store.write("active",value)}
    func beginRecording(){guard !readFailure && !activeReadFailure else{showError("保存データの復元が必要です。元のファイルを保護しています。");return};if active != nil {togglePause();return};let now=Date().timeIntervalSince1970*1000;active=["id":UUID().uuidString,"name":"さんぽ","start":now,"end":now,"pausedMs":0,"note":""];do{try persistActive();try recorder.start(id:active?["id"] as? String,start:now,recording:true);haptic()}catch{if recorder.session==nil {active=nil;try? store.write("active",nil)};showError(error.localizedDescription)}}
    func togglePause() {
        guard var value = active else { return }
        guard !readFailure && !activeReadFailure else {
            showError("中断した保存データの復元が必要です。")
            return
        }
        if activeWasSaved { retryFinalizedCleanup(); return }
        let now = Date().timeIntervalSince1970 * 1000
        do {
            if isRecording {
                try recorder.stop(end: false)
                value["pauseAt"] = now
                active = value
                try persistActive()
            } else {
                try adoptActiveIfNeeded()
                let previous = active
                let paused = nativeNumber(value["pausedMs"]) ?? 0
                value["pausedMs"] = paused + max(0, now - (nativeNumber(value["pauseAt"]) ?? now))
                value.removeValue(forKey: "pauseAt")
                active = value
                do {
                    try persistActive()
                    try recorder.start(id: value["id"] as? String, start: nativeNumber(value["start"]), recording: true)
                } catch {
                    active = previous
                    try? persistActive()
                    throw error
                }
            }
        } catch { showError(error.localizedDescription) }
        tick()
    }
    private func retryFinalizedCleanup() {
        do { try clearFinalizedRecording(); closeSheet() }
        catch { showError("さんぽは保存済みです。終了処理を再試行してください。\n" + error.localizedDescription) }
    }
    func finishRecording() {
        guard active != nil else { return }
        if activeWasSaved { retryFinalizedCleanup(); return }
        guard activePoints.count >= 2 else {
            showError("まだ道が記録されていません。位置情報を取得して少し歩いてから保存してください。")
            return
        }
        do {
            let now = Date().timeIntervalSince1970 * 1000
            if recorder.session != nil { try recorder.stop(end: false) }
            if active?["pauseAt"] == nil { active?["pauseAt"] = now }
            try persistActive()
            guard var value = active else { return }
            let cutoff = nativeTime(value["pauseAt"]) ?? now
            value["end"] = max(cutoff, activePoints.last?.t ?? cutoff)
            value["points"] = activePoints.map(\.json)
            value["duration"] = max(0, cutoff - (nativeNumber(value["start"]) ?? cutoff) - (nativeNumber(value["pausedMs"]) ?? 0))
            try updateLibrary { data in
                var list = data["walks"] as? [[String:Any]] ?? []
                if !list.contains(where: { $0["id"] as? String == value["id"] as? String }) { list.append(value) }
                data["walks"] = list
            }
            // From this point the walk is durable. Retries only clear recovery files.
            rebuildActiveExploration()
            try clearFinalizedRecording()
            closeSheet()
            haptic()
        } catch {
            tick()
            showError("保存または記録終了に失敗しました。記録は残しています。\n" + error.localizedDescription)
        }
    }
    func discardRecording() {
        do { try clearFinalizedRecording(); closeSheet() }
        catch { showError(error.localizedDescription) }
    }
    func renameWalk(id:String,name:String,note:String){do{try updateLibrary{data in var list=data["walks"] as? [[String:Any]] ?? [];if let index=list.firstIndex(where:{$0["id"] as? String==id}){list[index]["name"]=String(name.prefix(60));list[index]["note"]=String(note.prefix(3000))};data["walks"]=list}}catch{showError(error.localizedDescription)}}
    func deleteWalk(id:String){do{try updateLibrary{data in data["walks"]=(data["walks"] as? [[String:Any]] ?? []).filter{$0["id"] as? String != id}};rebuildActiveExploration();closeSheet()}catch{showError(error.localizedDescription)}}
    func exportWalk(id:String){guard let walk=walks.first(where:{$0.id==id})else{return};shareData(NativeTrackIO.gpx(walks:[walk]),name:"PlainWalk-"+id+".gpx")}
    func shareData(_ data:Data,name:String){do{let folder=FileManager.default.temporaryDirectory.appendingPathComponent("PlainWalk-"+UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);let url=folder.appendingPathComponent(URL(fileURLWithPath:name).lastPathComponent);try data.write(to:url,options:.atomic);present(.share(url))}catch{showError(error.localizedDescription)}}
    func exportBackup(){do{let data=readFailure ? try Data(contentsOf:store.url("library")) : try JSONSerialization.data(withJSONObject:library,options:[.sortedKeys]);shareData(data,name:"PlainWalk-backup.json")}catch{showError(error.localizedDescription)}}
    func importFiles(){afterClosing{self.importing=true}}
    func handleImport(_ result: Result<[URL],Error>) {
        Task {
            do {
                let urls = try result.get()
                guard let url = urls.first else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
                guard size <= 30_000_000 else { throw NativeError.message("ファイルが大きすぎます。") }
                let bytes = try Data(contentsOf: url)
                let fileName = url.lastPathComponent
                let payload = try await Task.detached(priority: .userInitiated) {
                    try Self.decodeImport(bytes, fileName: fileName)
                }.value
                if let incoming = payload.library {
                    try mergeImportedLibrary(incoming)
                } else if let paper = payload.sharedMap {
                    try updateLibrary { data in
                        var papers = data["sharedMaps"] as? [[String:Any]] ?? []
                        papers.append(paper)
                        data["sharedMaps"] = papers
                    }
                } else {
                    try updateLibrary { data in
                        var walks = data["walks"] as? [[String:Any]] ?? []
                        walks.append(contentsOf: payload.walks)
                        data["walks"] = walks
                    }
                }
                rebuildActiveExploration()
            } catch { showError(error.localizedDescription) }
        }
    }
    nonisolated private static func decodeImport(_ bytes: Data, fileName: String) throws -> NativeImportPayload {
        guard bytes.count <= 30_000_000 else { throw NativeError.message("ファイルが大きすぎます。") }
        guard URL(fileURLWithPath: fileName).pathExtension.lowercased() == "json" else {
            let walks = try NativeTrackIO.parse(data: bytes, fileName: fileName)
            var validation = NativeStore.emptyLibrary
            validation["walks"] = walks
            try NativeStore.validate(validation)
            return NativeImportPayload(walks: walks)
        }
        guard let incoming = try JSONSerialization.jsonObject(with: bytes) as? [String:Any] else {
            throw NativeError.message("バックアップを読み取れません。")
        }
        if incoming["type"] as? String == "plainwalk-white-map" {
            guard nativeNumber(incoming["version"]) == 1 else { throw NativeError.message("この白地図ファイルの版には対応していません。") }
            var validation = NativeStore.emptyLibrary
            validation["sharedMaps"] = [incoming]
            try NativeStore.validate(validation)
            let walks = (incoming["walks"] as? [[String:Any]] ?? []).map { walk -> [String:Any] in
                let points = (walk["points"] as? [[String:Any]] ?? []).compactMap { raw -> [String:Any]? in
                    guard let point = NativePoint(json: raw) else { return nil }
                    var result: [String:Any] = ["lat": point.lat, "lon": point.lon]
                    if point.isBreak { result["break"] = true }
                    return result
                }
                return ["id": walk["id"] as? String ?? UUID().uuidString, "points": points]
            }
            return NativeImportPayload(sharedMap: ["id": UUID().uuidString, "name": incoming["name"] as? String ?? "共有の白地図", "walks": walks])
        }
        try NativeStore.validate(incoming)
        return NativeImportPayload(library: incoming)
    }
    private func mergeImportedLibrary(_ incoming: [String:Any]) throws {
        var merged = readFailure ? incoming : library
        if !readFailure {
            for (key,value) in incoming where merged[key] == nil { merged[key] = value }
            for key in ["walks","spots","flags","bookmarks","doodles","sharedMaps"] {
                let old = merged[key] as? [[String:Any]] ?? []
                let ids = Set(old.compactMap { $0["id"] as? String })
                merged[key] = old + (incoming[key] as? [[String:Any]] ?? []).filter { item in
                    guard let id = item["id"] as? String else { return true }
                    return !ids.contains(id)
                }
            }
            var notes = merged["notes"] as? [String:Any] ?? [:]
            for (key,value) in incoming["notes"] as? [String:Any] ?? [:] where notes[key] == nil { notes[key] = value }
            merged["notes"] = notes
        }
        try NativeStore.validate(merged)
        try store.write("library", merged)
        library = merged
        readFailure = false
        rebuildLibrary()
    }
    #if DEBUG
    static func stateSelfTest() throws -> Bool {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("native-state-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = NativeStore(directory: folder)
        try store.write("library", NativeStore.emptyLibrary)
        let recovery: [String:Any] = [
            "id": "recovered-walk", "name": "Preserved name", "note": "Preserved note", "futureMetadata": ["keep": true],
            "start": 1_000.0, "pauseAt": 3_000.0, "pausedMs": 500.0,
            "points": [["lat": 35.0, "lon": 139.0, "t": 1_000.0, "accuracy": 5.0], ["lat": 35.0001, "lon": 139.0, "t": 2_000.0, "accuracy": 5.0]]
        ]
        try store.write("active", recovery)
        let model = NativeAppModel(store: store, runtimeServicesEnabled: false)
        guard model.isPaused, model.activePoints.count == 2, model.elapsed == 1.5 else {
            throw NativeError.message("The Web recovery snapshot did not restore as a paused native walk.")
        }
        try model.adoptActiveIfNeeded()
        let restoredRecorder = LocationRecorder(storageDirectory: folder)
        guard restoredRecorder.session?.points.count == 2 else {
            throw NativeError.message("Web-to-native migration was not durable.")
        }
        // A directory at the library destination forces the same atomic-write failure
        // as an unavailable persistence target, without touching the user's library.
        try FileManager.default.removeItem(at: store.url("library"))
        try FileManager.default.createDirectory(at: store.url("library"), withIntermediateDirectories: true)
        model.finishRecording()
        guard model.walks.isEmpty, model.activePoints.count == 2, model.isPaused, model.elapsed == 1.5,
              model.recorder.session?.points.count == 2 else {
            throw NativeError.message("A failed final save consumed the recovery state or counted paused time.")
        }
        try FileManager.default.removeItem(at: store.url("library"))
        model.finishRecording()
        guard model.walks.count == 1, model.activePoints.isEmpty, model.recorder.session == nil,
              let walk = model.walks.first, walk.duration == 1.5, walk.name == "Preserved name", walk.note == "Preserved note",
              (walk.raw["futureMetadata"] as? [String:Bool])?["keep"] == true else {
            throw NativeError.message("Retrying the final save lost metadata, duration, or duplicated the walk.")
        }
        // Simulate a crash after the walk was saved and before recovery cleanup.
        try FileManager.default.removeItem(at: store.url("active"))
        try FileManager.default.createDirectory(at: store.url("active"), withIntermediateDirectories: true)
        let recorder = LocationRecorder(storageDirectory: folder)
        let points = (recovery["points"] as? [[String:Any]] ?? []).compactMap(NativePoint.init(json:)).enumerated().map { index, point in
            RecordedPoint(lat: point.lat, lon: point.lon, t: point.t, accuracy: 5, seq: index + 1, gap: false)
        }
        try recorder.adoptRecoveredSession(id: "recovered-walk", start: 1_000, points: points)
        let duplicate = NativeAppModel(store: store, recorder: recorder, runtimeServicesEnabled: false)
        guard duplicate.activeWasSaved, duplicate.walks.count == 1, !duplicate.isRecording else {
            throw NativeError.message("A finalized walk was resurrected while recovery cleanup failed.")
        }
        duplicate.togglePause()
        guard !duplicate.isRecording, duplicate.walks.count == 1 else {
            throw NativeError.message("An already finalized ID was allowed to resume.")
        }
        try FileManager.default.removeItem(at: store.url("active"))
        duplicate.finishRecording()
        guard duplicate.active == nil, duplicate.walks.count == 1 else {
            throw NativeError.message("Finalized recovery cleanup could not be retried safely.")
        }
        return true
    }
    nonisolated static func importSelfTest() throws -> Bool {
        let paper: [String:Any] = [
            "type": "plainwalk-white-map", "version": 1, "id": "original-paper", "name": "Shared test",
            "privateFutureMetadata": "must not be imported as shared content",
            "walks": [["id": "selected-walk", "points": [["lat": 35.0, "lon": 139.0, "t": 1_000.0, "photo": "private", "break": true]]]]
        ]
        let bytes = try JSONSerialization.data(withJSONObject: paper)
        let imported = try decodeImport(bytes, fileName: "plainwalk-white-map.json")
        guard imported.library == nil, imported.walks.isEmpty, let shared = imported.sharedMap,
              shared["id"] as? String != "original-paper", shared["privateFutureMetadata"] == nil,
              let walk = (shared["walks"] as? [[String:Any]])?.first,
              let point = (walk["points"] as? [[String:Any]])?.first,
              point["t"] == nil, point["photo"] == nil, point["break"] as? Bool == true else {
            throw NativeError.message("Shared white-map import lost its coordinate-only boundary.")
        }
        var backup = NativeStore.emptyLibrary
        backup["unknownFutureField"] = ["preserved": true]
        let restored = try decodeImport(JSONSerialization.data(withJSONObject: backup), fileName: "backup.json")
        guard (restored.library?["unknownFutureField"] as? [String:Bool])?["preserved"] == true else {
            throw NativeError.message("Backup import discarded an unrecognized field.")
        }
        var invalid = paper
        invalid["walks"] = [["id": "invalid", "points": [["lat": 91.0, "lon": 139.0]]]]
        do { _ = try decodeImport(JSONSerialization.data(withJSONObject: invalid), fileName: "invalid.json") }
        catch { return true }
        throw NativeError.message("A shared white map with invalid coordinates was accepted.")
    }
    #endif
    func refreshSteps() {
        guard runtimeServicesEnabled else { return }
        lastStepRefresh = Date()
        stepRefreshRevision += 1
        let revision = stepRefreshRevision
        Task {
            var result: Double?
            do { result = try await recorder.motion.steps() } catch { }
            if config["healthEnabled"] as? Bool == true {
                do { if let healthSteps = try await HealthService().steps() { result = healthSteps } }
                catch { }
            }
            guard revision == stepRefreshRevision else { return }
            todaySteps = result.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        }
    }
    private func tick() {
        if let active {
            let now = Date().timeIntervalSince1970 * 1000
            elapsed = max(0, ((nativeNumber(active["pauseAt"]) ?? now) - (nativeNumber(active["start"]) ?? now) - (nativeNumber(active["pausedMs"]) ?? 0)) / 1000)
        } else { elapsed = 0 }
        let day = Calendar.current.startOfDay(for: Date())
        if day != lastDay {
            lastDay = day
            rebuildActiveExploration()
            refreshSteps()
        }
        if isRecording && Date().timeIntervalSince(lastStepRefresh) >= 30 { refreshSteps() }
    }
    func settingsAction(_ name:String){switch name {case "tab:map":tab = .map;closeSheet();case "tab:records":tab = .records;closeSheet();case "tab:profile":tab = .profile;closeSheet();case "nativeDeveloper":present(.developer);case "nativeImport","nativeRestore":importFiles();case "backup":exportBackup();case "gpxExportAll":shareData(NativeTrackIO.gpx(walks:walks),name:"PlainWalk-all.gpx");case "healthImport":present(.health);case "resetData":showError("記録の削除は、それぞれのさんぽ詳細から行えます。バックアップを書き出してから削除してください。");case "steps":present(.stepGoal);case "lutSettings":showError("写真のLUT編集は現在未実装です。元の写真でここいいなを保存できます。");case "about":showError("PlainWalk 互換クライアント 0.3.0。SwiftUI・MapKit・Core Locationで独立実装しています。");default:showError("手動GPS記録、写真・ノート、GPX、JSONバックアップに対応。自動開始、iCloud自動同期、近距離交換は未実装です。")}}
}
