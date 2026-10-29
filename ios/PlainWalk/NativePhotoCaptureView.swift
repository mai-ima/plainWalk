import SwiftUI
import PhotosUI
import UIKit
import AVKit
import ImageIO
import UniformTypeIdentifiers

/// A native capture flow. A pin is only saved against a recent real location fix.
@MainActor struct NativePhotoCaptureView: View {
    @ObservedObject var model: NativeAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var videoData: Data?
    @State private var videoURL: URL?
    @State private var mediaFolder: URL?
    @State private var player: AVPlayer?
    @State private var caption = ""
    @State private var emoji = "♡"
    @State private var videoMode = false
    @State private var camera = false
    @State private var processing = false
    @State private var capturePoint: NativePoint?
    @State private var captureTimestamp: Double?
    @State private var failure: String?
    private var availablePoint: NativePoint? {
        if let capturePoint { return capturePoint }
        guard let point = model.currentPoint, abs(point.t - Date().timeIntervalSince1970 * 1000) < 120_000, (point.accuracy ?? 0) <= 1000 else { return nil }; return point
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Group {
                        if let player { VideoPlayer(player: player).frame(height: 300) }
                        else if let imageData, let image = UIImage(data: imageData) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 340) }
                        else { VStack(spacing: 12) { Image(systemName: "camera").font(.system(size: 48)).foregroundStyle(.secondary); Text("歩いて見つけた「ここいいな」を残す").font(.subheadline).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).frame(height: 220).background(Color(uiColor: .secondarySystemBackground)) }
                    }.clipShape(RoundedRectangle(cornerRadius: 24))
                    Picker("撮影", selection: $videoMode) { Text("写真").tag(false); Text("2 秒の動画").tag(true) }.pickerStyle(.segmented)
                    HStack(spacing: 12) {
                        Button { Task { await openCamera() } } label: { Label(videoMode ? "動画を撮る" : "写真を撮る", systemImage: videoMode ? "video" : "camera").frame(maxWidth: .infinity).padding(.vertical, 11) }.buttonStyle(.borderedProminent).tint(.primary)
                        PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) { Label("写真を選ぶ", systemImage: "photo").frame(maxWidth: .infinity).padding(.vertical, 11) }.buttonStyle(.bordered)
                    }.disabled(processing)
                    if processing { ProgressView("写真・動画を準備しています…") }
                    TextField("どんなところでしたか？", text: $caption, axis: .vertical).lineLimit(3...6).padding(16).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 17))
                    HStack { Text("しるし"); Spacer(); Picker("しるし", selection: $emoji) { ForEach(["♡", "☕", "🌿", "🌸", "✨", "📷"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.menu) }
                    if let point = availablePoint { Label("現在地と一緒に、この端末に保存します。", systemImage: "location.fill").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).accessibilityValue("緯度 \(point.lat)、経度 \(point.lon)") }
                    else { VStack(alignment: .leading, spacing: 10) { Text("保存するには現在地の取得が必要です。位置情報を許可して、取得後に保存してください。").font(.footnote).foregroundStyle(.secondary); Button { model.locate() } label: { Label("現在地を取得", systemImage: "location") } }.frame(maxWidth: .infinity, alignment: .leading) }
                    if let failure { Text(failure).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading) }
                }.padding(20)
            }.navigationTitle("ここいいな").navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("残す") { save() }.disabled(availablePoint == nil || processing || (imageData == nil && videoData == nil && caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)) }
            }
        }.sheet(isPresented: $camera) { NCCameraPicker(video: videoMode) { result in camera = false; switch result { case .success(let media): Task { await receive(media) }; case .failure(let error): failure = error.localizedDescription } } }
            .onChange(of: photoItem) { _, item in guard let item else { return }; Task { await loadPhoto(item) } }
            .onDisappear { player?.pause(); if let mediaFolder { try? FileManager.default.removeItem(at: mediaFolder) } }
    }
    private func openCamera() async {
        failure = nil
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { failure = "この端末ではカメラを使えません。写真を選んでください。"; return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        var allowed = status == .authorized
        if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .video) }
        guard allowed else { failure = "カメラを使うには、iOS の設定で PlainWalk のカメラへのアクセスを許可してください。"; return }
        if videoMode, AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .audio) }
        camera = true
    }
    private func loadPhoto(_ item: PhotosPickerItem) async {
        processing = true; failure = nil; defer { processing = false; photoItem = nil }
        do { guard let bytes = try await item.loadTransferable(type: Data.self) else { throw NCCaptureError.message("写真を読み取れませんでした。") }; guard bytes.count <= 40_000_000 else { throw NCCaptureError.message("写真が大きすぎます。40 MB 以下の写真を選んでください。") }; let jpeg = try await Task.detached(priority: .userInitiated) { try ncCompressedPhoto(bytes) }.value; player?.pause(); player = nil; videoData = nil; imageData = jpeg; freezeLocation() } catch { failure = error.localizedDescription }
    }
    private func receive(_ media: NCCapturedMedia) async {
        processing = true; failure = nil; defer { processing = false }
        do {
            switch media {
            case .photo(let bytes): let jpeg = try await Task.detached(priority: .userInitiated) { try ncCompressedPhoto(bytes) }.value; player?.pause(); player = nil; videoData = nil; imageData = jpeg
            case .movie(let url):
                defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
                let asset = AVURLAsset(url: url); let duration = try await asset.load(.duration).seconds
                guard duration.isFinite, duration > 0, duration <= 2.6 else { throw NCCaptureError.message("2 秒以内の短い動画を撮影してください。") }
                let bytes = try Data(contentsOf: url); guard bytes.count <= 15_000_000 else { throw NCCaptureError.message("動画が大きすぎます。短く撮り直してください。") }
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("plainwalk-capture-" + UUID().uuidString, isDirectory: true); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); let saved = folder.appendingPathComponent("clip.mov"); try bytes.write(to: saved, options: .atomic)
                if let mediaFolder { try? FileManager.default.removeItem(at: mediaFolder) }; mediaFolder = folder; videoURL = saved; player?.pause(); player = AVPlayer(url: saved); videoData = bytes; imageData = nil
            }
            freezeLocation()
        } catch { failure = error.localizedDescription }
    }
    private func freezeLocation() { captureTimestamp = Date().timeIntervalSince1970 * 1000; capturePoint = nil; if let point = availablePoint { capturePoint = point } }
    private func save() {
        guard let point = availablePoint else { failure = "現在地を取得してから保存してください。"; return }
        var spot = point.json; spot["id"] = UUID().uuidString; spot["t"] = captureTimestamp ?? Date().timeIntervalSince1970 * 1000; spot["text"] = String(caption.prefix(240)); spot["emoji"] = emoji
        if let imageData { spot["photo"] = "data:image/jpeg;base64," + imageData.base64EncodedString() }
        if let videoData { spot["video"] = "data:video/quicktime;base64," + videoData.base64EncodedString(); spot["videoType"] = "video/quicktime" }
        do { try model.updateLibrary { library in var spots = library["spots"] as? [[String: Any]] ?? []; spots.append(spot); library["spots"] = spots }; UIImpactFeedbackGenerator(style: .light).impactOccurred(); dismiss() } catch { failure = error.localizedDescription }
    }
}
private enum NCCaptureError: LocalizedError { case message(String); var errorDescription: String? { switch self { case .message(let message): return message } } }
private enum NCCapturedMedia { case photo(Data), movie(URL) }
private func ncCompressedPhoto(_ bytes: Data) throws -> Data {
    guard let source = CGImageSourceCreateWithData(bytes as CFData, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1600, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw NCCaptureError.message("写真を読み取れませんでした。") }
    guard let output = CFDataCreateMutable(kCFAllocatorDefault, 0), let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw NCCaptureError.message("写真を保存できませんでした。") }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.83] as CFDictionary); guard CGImageDestinationFinalize(destination), CFDataGetLength(output) <= 3_500_000 else { throw NCCaptureError.message("写真を小さくできませんでした。別の写真でお試しください。") }; return output as Data
}
private struct NCCameraPicker: UIViewControllerRepresentable {
    let video: Bool
    let completion: (Result<NCCapturedMedia, Error>) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera; picker.delegate = context.coordinator; picker.mediaTypes = [video ? UTType.movie.identifier : UTType.image.identifier]
        if video { picker.cameraCaptureMode = .video; picker.videoMaximumDuration = 2; picker.videoQuality = .typeMedium } else { picker.cameraCaptureMode = .photo }; return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: NCCameraPicker; init(_ parent: NCCameraPicker) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            do {
                if let source = info[.mediaURL] as? URL {
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("plainwalk-camera-" + UUID().uuidString, isDirectory: true); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); let url = folder.appendingPathComponent("clip.mov"); try FileManager.default.copyItem(at: source, to: url); parent.completion(.success(.movie(url)))
                } else if let image = info[.originalImage] as? UIImage, let bytes = image.jpegData(compressionQuality: 0.92) { parent.completion(.success(.photo(bytes))) }
                else { throw NCCaptureError.message("撮影した写真・動画を読み取れませんでした。") }
            } catch { parent.completion(.failure(error)) }
        }
    }
}
