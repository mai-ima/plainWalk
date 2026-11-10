import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor struct NativeRootView: View {
    #if DEBUG
    @StateObject private var model=NativeScreenshotFixtures.makeModel()
    @State private var captureRoute:NativeCaptureDestination?
    @State private var captureContentReady=false
    #else
    @StateObject private var model=NativeAppModel()
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @State private var smokeStarted=false
    private var isSmoke: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-PlainWalkSmokeTest")
        #else
        return false
        #endif
    }
    var body: some View {
        #if DEBUG
        appContent.sheet(item:$captureRoute) { route in
            captureScreen(route.id).preferredColorScheme(model.colorScheme)
                .overlay {
                    if isSmoke && captureContentReady {
                        NativeSmokeAppearanceProbe(routeID:"capture:"+route.id,onReady:{markScreen("capture:"+route.id)},onWaiting:{markScreenTrace("capture:"+route.id,reason:$0)})
                            .frame(width:1,height:1).allowsHitTesting(false)
                    }
                }
        }
        #else
        appContent
        #endif
    }
    private var usesFixedTabBar: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    private var appContent:some View {
        VStack(spacing: 0) {
            TabView(selection:$model.tab) {
                NavigationStack {NativeMyMapView(model:model).toolbar(.hidden,for:.navigationBar).overlay {smokeProbe("map")}}.toolbar(usesFixedTabBar ? .hidden : .automatic, for: .tabBar).tabItem{Label("マイマップ",systemImage:"sparkles")}.tag(NativeTab.map)
                NavigationStack {NativeRecordsView(model:model).overlay { smokeProbe("records") }}.toolbar(usesFixedTabBar ? .hidden : .automatic, for: .tabBar).tabItem{Label("記録",systemImage:"chart.bar.fill")}.tag(NativeTab.records)
                NavigationStack(path: $model.profilePath) {
                    NativeProfileView(model:model).overlay { smokeProbe("profile") }.onAppear(perform:model.profileDidAppear)
                        .navigationDestination(for: NativeProfileDestination.self) { destination in
                            switch destination {
                            case .collection(let item):
                                NativeCollectionsView(model:model,collection:item)
                                    .overlay { smokeProbe("collection:"+item.rawValue) }
                            case .settings:
                                NativeSettingsView(config:model.config,onChange:model.saveConfig,onAction:model.settingsAction,onClose:model.closeSettings,embedded:true)
                                    .toolbar(.hidden,for:.navigationBar)
                                    .overlay { smokeProbe("settings") }
                            }
                        }
                }.toolbar(usesFixedTabBar ? .hidden : .automatic, for: .tabBar).tabItem{Label("プロフィール",systemImage:"person")}.tag(NativeTab.profile)
            }
            if usesFixedTabBar {
                NativeFixedTabBar(selected: model.tab) { tab in
                    guard model.tab != tab else { return }
                    model.tab = tab
                    model.haptic()
                }
            }
        }
        .tint(.primary).preferredColorScheme(model.colorScheme)
        .sheet(item:$model.sheet,onDismiss:model.sheetDismissed) {item in
            sheetContent(item).preferredColorScheme(model.colorScheme).overlay { smokeProbe(item.id.hasPrefix("noteEditor:") ? "noteEditor" : item.id) }
                .alert("お知らせ",isPresented:Binding(get:{model.errorMessage != nil && model.sheet != nil},set:{if !$0{model.errorMessage=nil}})){Button("閉じる",role:.cancel){model.errorMessage=nil}}message:{Text(model.errorMessage ?? "")}
        }
        .fullScreenCover(isPresented:$model.showingAnswer,onDismiss:model.sheetDismissed) {
            NativeAnswerMapView(model:model).preferredColorScheme(model.colorScheme)
                .overlay { smokeProbe("answer") }
                .alert("お知らせ",isPresented:Binding(get:{model.errorMessage != nil && model.showingAnswer},set:{if !$0{model.errorMessage=nil}})){Button("閉じる",role:.cancel){model.errorMessage=nil}}message:{Text(model.errorMessage ?? "")}
        }
        .fileImporter(isPresented:$model.importing,allowedContentTypes:[.json,.xml,UTType(filenameExtension:"gpx") ?? .data,UTType(filenameExtension:"tcx") ?? .data],allowsMultipleSelection:false,onCompletion:model.handleImport)
        .alert("お知らせ",isPresented:Binding(get:{model.errorMessage != nil && model.sheet==nil && !model.showingAnswer},set:{if !$0{model.errorMessage=nil}})){Button("閉じる",role:.cancel){model.errorMessage=nil}}message:{Text(model.errorMessage ?? "")}
        .onChange(of:scenePhase){_,phase in if phase == .active && !isSmoke {model.refreshSteps()} }
        .task{if !isSmoke {model.refreshSteps()};await runSmoke()}
    }
    #if DEBUG
    @ViewBuilder private func captureScreen(_ key:String)->some View {
        switch key {
        case "spotDetail","stickerPicker","bookmarkDetail","paperEditor","paperDetail","doodleEditor","doodleDetail","badgeDetail","noteSecondPage":
            nativeCaptureCollectionScreen(key,model:model,onContentReady:{captureContentReady=true})
        case "walkRename","day","week","walkPhoto","trackEditor":
            nativeCaptureRecordScreen(key,model:model)
        case "mapSpot","mapFlag": nativeCaptureMapScreen(key,model:model)
        case "answerSearch","answerSelection","answerSatellite","answer3D": nativeCaptureAnswerScreen(key,model:model)
        default: ContentUnavailableView("未定義の確認画面",systemImage:"exclamationmark.triangle",description:Text(key))
        }
    }
    #endif
    @ViewBuilder private func sheetContent(_ item:NativeSheet)->some View {
        switch item {
        case .settings: NativeSettingsView(config:model.config,onChange:{next in model.saveConfig(next)},onAction:model.settingsAction,onClose:model.closeSheet)
        case .stepGoal: NativeStepGoalView(model:model)
        case .lut: NativeLUTView(model:model)
        case .noteEditor(let day): NativeNotebookEditor(model:model,day:day)
        case .developer: NativeDeveloperView(recorder:model.recorder)
        case .layers: NativeLayerView(model:model)
        case .menu: NativeMenuView(model:model)
        case .answer: NativeAnswerMapView(model:model)
        case .spot: NativePhotoCaptureView(model:model)
        case .walk(let id): NativeWalkDetailView(model:model,walkID:id)
        case .collection(let item): NativeCollectionsView(model:model,collection:item,standalone:true)
        case .stats: NativeStatsView(model:model)
        case .replay(let id): NativeReplayView(model:model,walkID:id)
        case .share(let url): NativeShareView(url:url)
        case .health: NativeHealthImportView(model:model)
        }
    }
    @ViewBuilder private func smokeProbe(_ name: String) -> some View {
        #if DEBUG
        if isSmoke && smokeScreenIsCurrent(name) {
            NativeSmokeAppearanceProbe(routeID:name,onReady: { markScreen(name) }, onWaiting: { markScreenTrace(name, reason:$0) })
                .frame(width: 1, height: 1).allowsHitTesting(false)
        }
        #endif
    }
    private func smokeScreenIsCurrent(_ name:String)->Bool {
        if model.showingAnswer {return name == "answer"}
        if let sheet=model.sheet {
            return name == (sheet.id.hasPrefix("noteEditor:") ? "noteEditor" : sheet.id)
        }
        if model.tab == .map {return name == "map"}
        if model.tab == .records {return name == "records"}
        guard model.tab == .profile else {return false}
        switch model.profilePath.last {
        case .settings: return name == "settings"
        case .collection(let item): return name == "collection:"+item.rawValue
        case nil: return name == "profile"
        }
    }
    private func markScreen(_ name: String) {
        #if DEBUG
        guard isSmoke else { return }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PlainWalk")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? Data("ready".utf8).write(to: folder.appendingPathComponent("screen-" + name + ".ready"), options: .atomic)
        #endif
    }
    private func markScreenTrace(_ name:String,reason:String) {
        #if DEBUG
        guard isSmoke else {return}
        let folder=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("PlainWalk")
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        try? Data(reason.utf8).write(to:folder.appendingPathComponent("screen-"+name+".trace"),options:.atomic)
        #endif
    }
    private func runSmoke() async {
        #if DEBUG
        guard !smokeStarted, isSmoke else { return }
        smokeStarted = true
        do {
            let args = ProcessInfo.processInfo.arguments
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PlainWalk")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("self-tests-started".utf8).write(to:folder.appendingPathComponent("native-smoke-stage.txt"),options:.atomic)
            var checks: [String: Any] = ["ready":true,"nativeUI":true,"screenOnly":true]
            if !args.contains("-PlainWalkScreenOnly") {
            try Data("replay-movie-self-test".utf8).write(to:folder.appendingPathComponent("native-smoke-stage.txt"),options:.atomic)
            let movie = try await NativeReplayMovie.selfTest(previewURL:folder.appendingPathComponent("native-export-smoke.mp4"))
            checks = [
                "replayMovie": movie,
                "noteTransform": try NativeNoteTransform.selfTest(),
                "ready": true, "nativeUI": true,
                "recordingPersistence": try LocationRecorder.persistenceSelfTest(),
                "storage": try NativeStore.selfTest(),
                "trackMath": try NativeTrackMath.selfTest(),
                "trackIO": try NativeTrackIO.selfTest(),
                "importCompatibility": try NativeAppModel.importSelfTest(),
                "modelState": try NativeAppModel.stateSelfTest(),
                "mapCamera": try await NativeAnswerMapView.cameraSelfTest(),
                "mapProjection": try await NativeMyMapView.projectionSelfTest(),
                "trackEditor": try NativeTrackEditDraft.selfTest(),
                "photoEffects": try NativePhotoEffects.selfTest(),
                "photoMetadata": try NativePhotoMetadata.selfTest(),
                "boundaryGeometry": try NativeBoundaryGeometry.selfTest()
            ]
            }
            try JSONSerialization.data(withJSONObject: checks).write(to: folder.appendingPathComponent("native-ready.json"), options: .atomic)
            try Data("self-tests-complete; routing".utf8).write(to:folder.appendingPathComponent("native-smoke-stage.txt"),options:.atomic)
            if let capture=args.first(where:{$0.hasPrefix("-PlainWalkCapture=")})?.split(separator:"=",maxSplits:1).last {
                guard args.contains("-PlainWalkScreenshotFixture") else {throw NativeError.message("Capture routes require an isolated screenshot fixture.")}
                let key=String(capture)
                captureContentReady=key != "badgeDetail"
                captureRoute=NativeCaptureDestination(id:key)
                return
            }
            if args.contains("-PlainWalkNativeSettingsSmokeTest") { model.openSettings() }
            if let route = args.first(where: { $0.hasPrefix("-PlainWalkScreen=") })?.split(separator: "=").last {
                switch String(route) {
                case "settings": model.openSettings()
                case "stats": model.present(.stats)
                case "replayAll": model.present(.replay(nil))
                case "replayWalk": model.present(.replay(NativeScreenshotFixtures.walkID))
                case "walk": model.present(.walk(NativeScreenshotFixtures.walkID))
                case "health": model.present(.health)
                case "records": model.tab = .records
                case "profile": model.tab = .profile
                case "layers": model.openLayers()
                case "answer": model.openAnswerMap()
                case "spots": model.openCollection(.spots)
                case "doodles": model.openCollection(.doodles)
                case "menu": model.openMenu()
                case "stepGoal": model.present(.stepGoal)
                case "developer": model.present(.developer)
                case "lut": model.present(.lut)
                case "spot": model.openSpotCapture()
                case "noteEditor":
                    let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.calendar=Calendar(identifier:.gregorian);formatter.dateFormat="yyyy-MM-dd"
                    model.present(.noteEditor(formatter.string(from:Date())))
                default:
                    if route.hasPrefix("collection:"),let collection=NativeCollection(rawValue:String(route.dropFirst("collection:".count))) {model.openCollection(collection)}
                }
            }
        } catch {
            NSLog("PlainWalk native smoke failed: %@", error.localizedDescription)
            model.showError("Native smoke check: " + error.localizedDescription)
        }
        #endif
    }
}

struct NativeShareView:UIViewControllerRepresentable {
    let url:URL
    func makeUIViewController(context:Context)->UIActivityViewController {
        let controller = UIActivityViewController(activityItems:[url],applicationActivities:nil)
        let folder = url.deletingLastPathComponent()
        controller.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: folder) }
        return controller
    }
    func updateUIViewController(_ uiViewController:UIActivityViewController,context:Context){}
}

#if DEBUG
/// Attach the probe's actual drawn UIView to the visible route overlay. It does
/// not introduce a child controller that SwiftUI can retain outside the window.
@MainActor private struct NativeSmokeAppearanceProbe: UIViewRepresentable {
    let routeID: String
    let onReady: () -> Void
    let onWaiting: (String) -> Void
    func makeUIView(context: Context) -> Surface {
        Surface(routeID:routeID,onReady:onReady,onWaiting:onWaiting)
    }
    func updateUIView(_ surface: Surface, context: Context) {
        surface.update(routeID:routeID,onReady:onReady,onWaiting:onWaiting)
    }
    static func dismantleUIView(_ surface: Surface, coordinator: ()) { surface.invalidate() }
    final class Surface: UIView {
        private var routeID: String
        private let probeID = UUID().uuidString
        private var onReady: () -> Void
        private var onWaiting: (String) -> Void
        private var lastReason=""
        private var sent=false
        private var hasDrawn=false
        private var pending: Task<Void,Never>?
        private var expected: Visibility?
        private var waitingTransitions: [AnyObject] = []
        private var completedTransitions: [AnyObject] = []
        private struct Visibility: Equatable {
            let window: ObjectIdentifier
            let rect: CGRect
            let bounds: CGRect
            let ancestors: [ObjectIdentifier]
            let controllers: [ObjectIdentifier]
        }
        init(routeID: String,onReady: @escaping () -> Void,onWaiting: @escaping (String)->Void) {
            self.routeID=routeID;self.onReady=onReady;self.onWaiting=onWaiting
            super.init(frame:.zero)
            backgroundColor = .clear;isOpaque=false;isUserInteractionEnabled=false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        func update(routeID: String,onReady: @escaping () -> Void,onWaiting: @escaping (String)->Void) {
            if self.routeID != routeID {
                invalidate();sent=false;hasDrawn=false;lastReason=""
                waitingTransitions=[];completedTransitions=[]
                self.routeID=routeID;setNeedsDisplay()
            }
            self.onReady=onReady;self.onWaiting=onWaiting
            observeVisibility()
        }
        override func didMoveToSuperview() {
            super.didMoveToSuperview();invalidate();hasDrawn=false
            observeVisibility();if window != nil {setNeedsDisplay()}
        }
        override func didMoveToWindow() {
            super.didMoveToWindow();invalidate();hasDrawn=false
            observeVisibility();if window != nil {setNeedsDisplay()}
        }
        override func layoutSubviews() {super.layoutSubviews();setNeedsDisplay();observeVisibility()}
        override func draw(_ rect:CGRect) {super.draw(rect);hasDrawn=true;observeVisibility()}
        func invalidate() {pending?.cancel();pending=nil;expected=nil}
        private func observeVisibility() {
            guard !sent else {return}
            guard let visible=visibility() else {invalidate();return}
            if expected==visible,pending != nil {return}
            invalidate();expected=visible
            record("visible; waiting for stable draw")
            // This settle check can only start from an attached, drawn surface.
            // Recheck the exact window, geometry, ancestry and host after 0.5s.
            pending=Task { @MainActor [weak self] in
                do {try await Task.sleep(nanoseconds:500_000_000)} catch {return}
                guard !Task.isCancelled,let self else {return}
                self.pending=nil
                guard self.expected==visible,self.visibility()==visible else {self.invalidate();return}
                self.sent=true;self.expected=nil;self.waitingTransitions=[];self.completedTransitions=[]
                self.record("ready");self.onReady()
            }
        }
        private func hostingControllers() -> [UIViewController] {
            var controllers:[UIViewController]=[],seen=Set<ObjectIdentifier>()
            var responder:UIResponder?=self
            while let current=responder {
                if let controller=current as? UIViewController {
                    var host:UIViewController?=controller
                    while let candidate=host {
                        if seen.insert(ObjectIdentifier(candidate)).inserted {controllers.append(candidate)}
                        host=candidate.parent
                    }
                }
                responder=current.next
            }
            return controllers
        }
        private func waitForTransition(_ coordinator:any UIViewControllerTransitionCoordinator) -> Bool {
            let object=coordinator as AnyObject
            if completedTransitions.contains(where:{$0===object}) {return false}
            if !waitingTransitions.contains(where:{$0===object}) {
                waitingTransitions.append(object)
                let registered=coordinator.animate(alongsideTransition:{ _ in }) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self else {return}
                        self.waitingTransitions.removeAll {$0===object}
                        self.completedTransitions.append(object)
                        self.observeVisibility()
                    }
                }
                if !registered {
                    // Failed registration establishes no completion. A subsequent
                    // real lifecycle/draw event must observe this state again.
                    waitingTransitions.removeAll {$0===object}
                    return true
                }
            }
            return true
        }
        private func record(_ reason:String) {
            let hosts=hostingControllers().map {String(describing:type(of:$0))}.joined(separator:">")
            let detail="route=\(routeID); probe=\(probeID); window=\(window.map {String(describing:ObjectIdentifier($0))} ?? "none"); bounds=\(bounds); rect=\(window.map {convert(bounds,to:$0)} ?? .zero); drawn=\(hasDrawn); hosts=\(hosts); \(reason)"
            guard lastReason != detail else {return}
            lastReason=detail;onWaiting(detail)
        }
        private func blocked(_ reason:String)->Visibility? {record(reason);return nil}
        private func visibility() -> Visibility? {
            guard let window else {return blocked("surface outside window")}
            guard hasDrawn else {return blocked("surface has not drawn")}
            guard !window.isHidden,window.alpha>0.01,
                  bounds.width>0,bounds.height>0 else {return blocked("window hidden or zero surface bounds")}
            let rect=convert(bounds,to:window)
            guard rect.origin.x.isFinite,rect.origin.y.isFinite,rect.width.isFinite,rect.height.isFinite,
                  window.bounds.contains(rect) else {return blocked("surface outside window bounds: \(rect)")}
            var views:[ObjectIdentifier]=[],ancestor:UIView?=self
            while let current=ancestor {
                guard !current.isHidden,current.alpha>0.01 else {return blocked("hidden ancestor: \(type(of:current))")}
                if current.clipsToBounds,!current.convert(current.bounds,to:window).contains(rect) {
                    return blocked("clipped ancestor: \(type(of:current))")
                }
                views.append(ObjectIdentifier(current));ancestor=current.superview
            }
            let controllers=hostingControllers()
            guard !controllers.isEmpty else {return blocked("no hosting controller in responder chain")}
            for current in controllers {
                guard !current.isBeingDismissed else {return blocked("controller dismissing: \(type(of:current))")}
                // Gate on the actual visible hosting chain and UIView ancestry,
                // without assuming any probe controller belongs to that chain.
                if let cover=current.presentedViewController,let coverView=cover.viewIfLoaded,coverView.window != nil,
                   !cover.isBeingDismissed,!isDescendant(of:coverView) {return blocked("covered by modal: \(type(of:cover))")}
                if let transition=current.transitionCoordinator,waitForTransition(transition) {return blocked("waiting for transition: \(type(of:current))")}
                if current.isBeingPresented {return blocked("controller presenting: \(type(of:current))")}
            }
            return Visibility(window:ObjectIdentifier(window),rect:rect,bounds:bounds,ancestors:views,controllers:controllers.map {ObjectIdentifier($0)})
        }
    }
}
#endif

#if DEBUG
private struct NativeCaptureDestination:Identifiable {let id:String}
#endif
