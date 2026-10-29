import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor struct NativeRootView: View {
    @StateObject private var model=NativeAppModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var smokeStarted=false
    var body: some View {
        TabView(selection:$model.tab) {
            NavigationStack {NativeMyMapView(model:model).toolbar(.hidden,for:.navigationBar)}.tabItem{Label("マイマップ",systemImage:"sparkles")}.tag(NativeTab.map)
            NavigationStack {NativeRecordsView(model:model)}.tabItem{Label("記録",systemImage:"chart.bar.fill")}.tag(NativeTab.records)
            NavigationStack {NativeProfileView(model:model)}.tabItem{Label("プロフィール",systemImage:"person")}.tag(NativeTab.profile)
        }
        .tint(.primary).preferredColorScheme(model.colorScheme)
        .sheet(item:$model.sheet,onDismiss:model.sheetDismissed) {item in
            sheetContent(item).preferredColorScheme(model.colorScheme)
                .alert("お知らせ",isPresented:Binding(get:{model.errorMessage != nil && model.sheet != nil},set:{if !$0{model.errorMessage=nil}})){Button("閉じる",role:.cancel){model.errorMessage=nil}}message:{Text(model.errorMessage ?? "")}
        }
        .fileImporter(isPresented:$model.importing,allowedContentTypes:[.json,.xml,UTType(filenameExtension:"gpx") ?? .data,UTType(filenameExtension:"tcx") ?? .data],allowsMultipleSelection:false,onCompletion:model.handleImport)
        .alert("お知らせ",isPresented:Binding(get:{model.errorMessage != nil && model.sheet==nil},set:{if !$0{model.errorMessage=nil}})){Button("閉じる",role:.cancel){model.errorMessage=nil}}message:{Text(model.errorMessage ?? "")}
        .onChange(of:scenePhase){_,phase in if phase == .active {model.refreshSteps()} }
        .task{model.refreshSteps();runSmoke()}
    }
    @ViewBuilder private func sheetContent(_ item:NativeSheet)->some View {
        switch item {
        case .settings: NativeSettingsView(config:model.config,onChange:{next in model.saveConfig(next)},onAction:model.settingsAction,onClose:model.closeSheet)
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
    private func runSmoke(){
        #if DEBUG
        guard !smokeStarted,ProcessInfo.processInfo.arguments.contains("-PlainWalkSmokeTest")else{return};smokeStarted=true
        do{let persistence=try LocationRecorder.persistenceSelfTest();let storage=try NativeStore.selfTest();let math=try NativeTrackMath.selfTest();let trackIO=try NativeTrackIO.selfTest();let data:[String:Any]=["ready":true,"nativeUI":true,"recordingPersistence":persistence,"storage":storage,"trackMath":math,"trackIO":trackIO];let folder=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("PlainWalk");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try JSONSerialization.data(withJSONObject:data).write(to:folder.appendingPathComponent("native-ready.json"),options:.atomic)
            if ProcessInfo.processInfo.arguments.contains("-PlainWalkNativeSettingsSmokeTest"){model.openSettings()}
        }catch{model.showError("Native smoke check: "+error.localizedDescription)}
        #endif
    }
}

struct NativeShareView:UIViewControllerRepresentable {
    let url:URL
    func makeUIViewController(context:Context)->UIActivityViewController{UIActivityViewController(activityItems:[url],applicationActivities:nil)}
    func updateUIViewController(_ uiViewController:UIActivityViewController,context:Context){}
}
