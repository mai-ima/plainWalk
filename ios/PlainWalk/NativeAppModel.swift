import SwiftUI
import CoreLocation
import Combine
import UniformTypeIdentifiers

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
    let recorder = LocationRecorder()
    private let store = NativeStore()
    private let activity = LiveActivityService()
    private var active: [String:Any]?
    private var readFailure = false
    private var activeReadFailure = false
    private let doodleProgress = NativeDoodleProgress()
    private var explored = Set<String>()
    private var activeExplored = Set<String>()
    private var activePioneered = 0.0
    private var recorderDistanceOffset = 0.0
    private var queuedSheet: NativeSheet?
    private var afterDismiss: (() -> Void)?
    private var clock: AnyCancellable?
    private var savedToday = 0.0
    private var savedTotal = 0.0
    private var lastDay = Calendar.current.startOfDay(for:Date())
    var distanceUnit: String { config["units"] as? String == "mi" ? "mi" : "km" }
    private var palette: NativeLayerPalette { let index=Int(min(Double(NativeLayerPalette.all.count-1),max(0,nativeNumber(config["theme"]) ?? 0)));return NativeLayerPalette.all[index] }
    var paper: Color { colorScheme == .dark ? Color(red:0.07,green:0.08,blue:0.075) : palette.paper }
    var ink: Color { colorScheme == .dark ? .white : palette.ink }
    var colorScheme: ColorScheme? { switch config["dark"] as? String {case "dark":return .dark;case "light":return .light;default:return nil} }
    init() {
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
        recorder.onPoint={ [weak self] point,id in self?.receive(point,id:id) }
        recorder.onSession={ [weak self] session in
            guard let self else{return};let wasRecording=self.isRecording;self.isRecording=session?.recording ?? false;self.isPaused=self.active != nil && !self.isRecording;if let session{self.recordingDistance=session.distance+self.recorderDistanceOffset};self.activity.update(session)
            if wasRecording && !self.isRecording && self.active != nil && self.active?["pauseAt"] == nil {self.active?["pauseAt"]=Date().timeIntervalSince1970*1000;do{try self.persistActive()}catch{self.showError(error.localizedDescription)}}
            UIApplication.shared.isIdleTimerDisabled=self.isRecording && self.config["wake"] as? Bool == true
        }
        if let issue=recorder.recoveryIssue {showError(issue)}
        clock=Timer.publish(every:1,on:.main,in:.common).autoconnect().sink { [weak self] _ in self?.tick() }
        tick()
    }
    func haptic() { UIImpactFeedbackGenerator(style:.light).impactOccurred() }
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
        active=nil;activeReadFailure=false;activePoints=[];activeExplored=[];activePioneered=0;recorderDistanceOffset=0
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
        explored=[];for walk in values where walk.points.count>1 {for i in 1..<walk.points.count where !walk.points[i].isBreak {explored.formUnion(NativeTrackMath.cellKeys(walk.points[i-1],walk.points[i]))}}
        refreshTotals();libraryRevision+=1
    }
    private func refreshTotals(){let day=Calendar.current.startOfDay(for:Date());savedTotal=walks.reduce(0){$0+$1.pioneered};savedToday=walks.filter{Calendar.current.isDate(Date(timeIntervalSince1970:$0.start/1000),inSameDayAs:day)}.reduce(0){$0+$1.pioneered};totalPioneered=savedTotal+activePioneered;todayPioneered=savedToday+activePioneered}
    private func rebuildActiveExploration(){activeExplored=[];activePioneered=0;if !activeWasSaved && activePoints.count>1 {for i in 1..<activePoints.count {appendExploration(activePoints[i-1],activePoints[i])}};refreshTotals()}
    private func appendExploration(_ a:NativePoint,_ b:NativePoint){guard !b.isBreak else{return};let keys=NativeTrackMath.cellKeys(a,b);guard !keys.isEmpty else{return};let fresh=keys.filter{!explored.contains($0) && !activeExplored.contains($0)}.count;activePioneered+=NativeTrackMath.distance(a,b)*Double(fresh)/Double(keys.count);activeExplored.formUnion(keys)}
    private func receive(_ value:RecordedPoint,id:String?){let point=NativePoint(value);currentPoint=point;accuracy=value.accuracy;guard let id,id==active?["id"] as? String,!activeWasSaved else{return};if let last=activePoints.last {guard point.t>last.t else{return};appendExploration(last,point)};activePoints.append(point);recordingDistance=(recorder.session?.distance ?? 0)+recorderDistanceOffset;totalPioneered=savedTotal+activePioneered;todayPioneered=savedToday+activePioneered
        let completions=doodleProgress.completedPoints(in:library["doodles"] as? [[String:Any]] ?? [],at:point,revision:libraryRevision)
        if !completions.isEmpty {do{try updateLibrary{data in data["doodles"]=NativeDoodleProgress.applying(completions,to:data["doodles"] as? [[String:Any]] ?? [])};doodleProgress.didApply(revision:libraryRevision)}catch{showError(error.localizedDescription)}}
    }
    private func persistActive() throws {guard var value=active else{try store.write("active",nil);return};value["points"]=activePoints.map(\.json);try store.write("active",value)}
    func beginRecording(){guard !readFailure && !activeReadFailure else{showError("保存データの復元が必要です。元のファイルを保護しています。");return};if active != nil {togglePause();return};let now=Date().timeIntervalSince1970*1000;active=["id":UUID().uuidString,"name":"さんぽ","start":now,"end":now,"pausedMs":0,"note":""];do{try persistActive();try recorder.start(id:active?["id"] as? String,start:now,recording:true);haptic()}catch{if recorder.session==nil {active=nil;try? store.write("active",nil)};showError(error.localizedDescription)}}
    func togglePause(){guard var value=active else{return};guard !readFailure && !activeReadFailure else{showError("中断した保存データの復元が必要です。");return};if activeWasSaved {do{try clearFinalizedRecording();closeSheet()}catch{showError("さんぽは保存済みです。終了処理を再試行してください。\n"+error.localizedDescription)};return};let now=Date().timeIntervalSince1970*1000
        do {if isRecording {try recorder.stop(end:false);value["pauseAt"]=now;active=value;try persistActive()}else{try adoptActiveIfNeeded();let paused=nativeNumber(value["pausedMs"]) ?? 0;value["pausedMs"]=paused+max(0,now-(nativeNumber(value["pauseAt"]) ?? now));value.removeValue(forKey:"pauseAt");let previous=active;active=value;do{try persistActive();try recorder.start(id:value["id"] as? String,start:nativeNumber(value["start"]),recording:true)}catch{active=previous;try? persistActive();throw error}}}catch{showError(error.localizedDescription)};tick()
    }
    func finishRecording(){guard active != nil else{return};if activeWasSaved {do{try clearFinalizedRecording();closeSheet()}catch{showError("さんぽは保存済みです。終了処理を再試行してください。\n"+error.localizedDescription)};return};guard activePoints.count>=2 else{showError("まだ道が記録されていません。位置情報を取得して少し歩いてから保存してください。");return}
        do {let now=Date().timeIntervalSince1970*1000;if recorder.session != nil {try recorder.stop(end:false)};if active?["pauseAt"]==nil{active?["pauseAt"]=now};try persistActive();guard var value=active else{return};let cutoff=nativeTime(value["pauseAt"]) ?? now;value["end"]=max(cutoff,activePoints.last?.t ?? cutoff);value["points"]=activePoints.map(\.json);value["duration"]=max(0,cutoff-(nativeNumber(value["start"]) ?? cutoff)-(nativeNumber(value["pausedMs"]) ?? 0));try updateLibrary{data in var list=data["walks"] as? [[String:Any]] ?? [];if !list.contains(where:{$0["id"] as? String==value["id"] as? String}){list.append(value)};data["walks"]=list};rebuildActiveExploration();try clearFinalizedRecording();closeSheet();haptic()}catch{tick();showError("保存または記録終了に失敗しました。記録は残しています。\n"+error.localizedDescription)}
    }
    func discardRecording(){do{try recorder.stop(end:true);try store.write("active",nil);active=nil;activePoints=[];activePioneered=0;activeExplored=[];isRecording=false;isPaused=false;recordingDistance=0;refreshTotals();closeSheet()}catch{showError(error.localizedDescription)}}
    func renameWalk(id:String,name:String,note:String){do{try updateLibrary{data in var list=data["walks"] as? [[String:Any]] ?? [];if let index=list.firstIndex(where:{$0["id"] as? String==id}){list[index]["name"]=String(name.prefix(60));list[index]["note"]=String(note.prefix(3000))};data["walks"]=list}}catch{showError(error.localizedDescription)}}
    func deleteWalk(id:String){do{try updateLibrary{data in data["walks"]=(data["walks"] as? [[String:Any]] ?? []).filter{$0["id"] as? String != id}};rebuildActiveExploration();closeSheet()}catch{showError(error.localizedDescription)}}
    func exportWalk(id:String){guard let walk=walks.first(where:{$0.id==id})else{return};shareData(NativeTrackIO.gpx(walks:[walk]),name:"PlainWalk-"+id+".gpx")}
    func shareData(_ data:Data,name:String){do{let folder=FileManager.default.temporaryDirectory.appendingPathComponent("PlainWalk-"+UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);let url=folder.appendingPathComponent(URL(fileURLWithPath:name).lastPathComponent);try data.write(to:url,options:.atomic);present(.share(url))}catch{showError(error.localizedDescription)}}
    func exportBackup(){do{let data=readFailure ? try Data(contentsOf:store.url("library")) : try JSONSerialization.data(withJSONObject:library,options:[.sortedKeys]);shareData(data,name:"PlainWalk-backup.json")}catch{showError(error.localizedDescription)}}
    func importFiles(){afterClosing{self.importing=true}}
    func handleImport(_ result:Result<[URL],Error>){do{let urls=try result.get();guard let url=urls.first else{return};let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}};let size=(try url.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0;guard size<=30_000_000 else{throw NativeError.message("ファイルが大きすぎます。")};let bytes=try Data(contentsOf:url)
        if url.pathExtension.lowercased()=="json" {guard let incoming=try JSONSerialization.jsonObject(with:bytes) as? [String:Any] else{throw NativeError.message("バックアップを読み取れません。")};try NativeStore.validate(incoming);var merged=readFailure ? incoming : library;if !readFailure {for (key,value) in incoming where merged[key]==nil {merged[key]=value};for key in ["walks","spots","flags","bookmarks","doodles","sharedMaps"]{let old=merged[key] as? [[String:Any]] ?? [];let ids=Set(old.compactMap{$0["id"] as? String});merged[key]=old+(incoming[key] as? [[String:Any]] ?? []).filter{item in guard let id=item["id"] as? String else{return true};return !ids.contains(id)}};var notes=merged["notes"] as? [String:Any] ?? [:];for (key,value) in incoming["notes"] as? [String:Any] ?? [:] where notes[key]==nil{notes[key]=value};merged["notes"]=notes};try NativeStore.validate(merged);try store.write("library",merged);library=merged;readFailure=false;rebuildLibrary()
        }else{let added=try NativeTrackIO.parse(data:bytes,fileName:url.lastPathComponent);try updateLibrary{data in var list=data["walks"] as? [[String:Any]] ?? [];list.append(contentsOf:added);data["walks"]=list}}
        rebuildActiveExploration()
    }catch{showError(error.localizedDescription)}}
    func refreshSteps(){Task{do{todaySteps=try await recorder.motion.steps();if config["healthEnabled"] as? Bool == true {todaySteps=try await HealthService().steps() ?? todaySteps}}catch{todaySteps=nil}}}
    private func tick(){if let active {let now=Date().timeIntervalSince1970*1000;elapsed=max(0,((nativeNumber(active["pauseAt"]) ?? now)-(nativeNumber(active["start"]) ?? now)-(nativeNumber(active["pausedMs"]) ?? 0))/1000)}else{elapsed=0};let day=Calendar.current.startOfDay(for:Date());if day != lastDay{lastDay=day;refreshTotals();refreshSteps()}}
    func settingsAction(_ name:String){switch name {case "tab:map":tab = .map;closeSheet();case "tab:records":tab = .records;closeSheet();case "tab:profile":tab = .profile;closeSheet();case "nativeDeveloper":present(.developer);case "nativeImport","nativeRestore":importFiles();case "backup":exportBackup();case "gpxExportAll":shareData(NativeTrackIO.gpx(walks:walks),name:"PlainWalk-all.gpx");case "healthImport":present(.health);case "resetData":showError("記録の削除は、それぞれのさんぽ詳細から行えます。バックアップを書き出してから削除してください。");case "steps":showError("今日の歩数はモーション、または許可したヘルスケアから取得します。データを取得できない場合は — と表示します。");case "lutSettings":showError("写真のLUT編集は現在未実装です。元の写真でここいいなを保存できます。");case "about":showError("PlainWalk 互換クライアント 0.3.0。SwiftUI・MapKit・Core Locationで独立実装しています。");default:showError("手動GPS記録、写真・ノート、GPX、JSONバックアップに対応。自動開始、iCloud自動同期、近距離交換は未実装です。")}}
}
