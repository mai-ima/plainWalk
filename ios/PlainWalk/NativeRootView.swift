import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor struct NativeRootView: View {
    @StateObject private var model=NativeAppModel()
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
        TabView(selection:$model.tab) {
            NavigationStack {NativeMyMapView(model:model).toolbar(.hidden,for:.navigationBar)}.tabItem{Label("マイマップ",systemImage:"sparkles")}.tag(NativeTab.map)
            NavigationStack {NativeRecordsView(model:model).background { smokeProbe("records") }}.tabItem{Label("記録",systemImage:"chart.bar.fill")}.tag(NativeTab.records)
            NavigationStack {NativeProfileView(model:model).background { smokeProbe("profile") }}.tabItem{Label("プロフィール",systemImage:"person")}.tag(NativeTab.profile)
        }
        .tint(.primary).preferredColorScheme(model.colorScheme)
        .sheet(item:$model.sheet,onDismiss:model.sheetDismissed) {item in
            sheetContent(item).preferredColorScheme(model.colorScheme).background { smokeProbe(item.id) }
                .alert("お知らせ",isPresented:Binding(get:{model.errorMessage != nil && model.sheet != nil},set:{if !$0{model.errorMessage=nil}})){Button("閉じる",role:.cancel){model.errorMessage=nil}}message:{Text(model.errorMessage ?? "")}
        }
        .fileImporter(isPresented:$model.importing,allowedContentTypes:[.json,.xml,UTType(filenameExtension:"gpx") ?? .data,UTType(filenameExtension:"tcx") ?? .data],allowsMultipleSelection:false,onCompletion:model.handleImport)
        .alert("お知らせ",isPresented:Binding(get:{model.errorMessage != nil && model.sheet==nil},set:{if !$0{model.errorMessage=nil}})){Button("閉じる",role:.cancel){model.errorMessage=nil}}message:{Text(model.errorMessage ?? "")}
        .onChange(of:scenePhase){_,phase in if phase == .active && !isSmoke {model.refreshSteps()} }
        .task{if !isSmoke {model.refreshSteps()};runSmoke()}
    }
    @ViewBuilder private func sheetContent(_ item:NativeSheet)->some View {
        switch item {
        case .settings: NativeSettingsView(config:model.config,onChange:{next in model.saveConfig(next)},onAction:model.settingsAction,onClose:model.closeSheet)
        case .stepGoal: NativeStepGoalView(model:model)
        case .developer: NativeDeveloperView(recorder:model.recorder)
        case .layers: NativeLayerView(model:model)
        case .menu: NativeMenuView(model:model)
        case .answer: NativeAnswerMapView(model:model)
        case .spot: NativePhotoCaptureView(model:model)
        case .walk(let id): NativeWalkDetailView(model:model,walkID:id)
        case .collection(let item): NativeCollectionsView(model:model,collection:item)
        case .stats: NativeStatsView(model:model)
        case .replay(let id): NativeReplayView(model:model,walkID:id)
        case .share(let url): NativeShareView(url:url)
        case .health: NativeHealthImportView(model:model)
        }
    }
    @ViewBuilder private func smokeProbe(_ name: String) -> some View {
        if isSmoke {
            NativeSmokeAppearanceProbe(onReady: { markScreen(name) })
                .frame(width: 1, height: 1).allowsHitTesting(false)
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
    private func runSmoke() {
        #if DEBUG
        guard !smokeStarted, isSmoke else { return }
        smokeStarted = true
        do {
            let checks: [String: Any] = [
                "ready": true, "nativeUI": true,
                "recordingPersistence": try LocationRecorder.persistenceSelfTest(),
                "storage": try NativeStore.selfTest(),
                "trackMath": try NativeTrackMath.selfTest(),
                "trackIO": try NativeTrackIO.selfTest(),
                "importCompatibility": try NativeAppModel.importSelfTest(),
                "modelState": try NativeAppModel.stateSelfTest(),
                "mapCamera": try NativeAnswerMapView.cameraSelfTest()
            ]
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PlainWalk")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: checks).write(to: folder.appendingPathComponent("native-ready.json"), options: .atomic)
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-PlainWalkNativeSettingsSmokeTest") { model.openSettings() }
            if let route = args.first(where: { $0.hasPrefix("-PlainWalkScreen=") })?.split(separator: "=").last {
                switch String(route) {
                case "records": model.tab = .records
                case "profile": model.tab = .profile
                case "layers": model.openLayers()
                case "answer": model.openAnswerMap()
                case "spots": model.openCollection(.spots)
                case "doodles": model.openCollection(.doodles)
                case "menu": model.openMenu()
                case "stepGoal": model.present(.stepGoal)
                case "developer": model.present(.developer)
                default: break
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

/// The DEBUG smoke route waits for UIKit presentation completion, rather than
/// SwiftUI onAppear, which can run before the sheet is visible on a slow Simulator.
private struct NativeSmokeAppearanceProbe: UIViewControllerRepresentable {
    let onReady: () -> Void
    func makeUIViewController(context: Context) -> Controller { Controller(onReady: onReady) }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.onReady = onReady }
    final class Controller: UIViewController {
        var onReady: () -> Void
        init(onReady: @escaping () -> Void) { self.onReady = onReady; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func loadView() { let content = UIView(); content.backgroundColor = .clear; view = content }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.viewIfLoaded?.window != nil, !self.isBeingDismissed else { return }
                self.onReady()
            }
        }
    }
}
