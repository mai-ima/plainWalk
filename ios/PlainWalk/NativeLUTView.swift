import SwiftUI
import UIKit
import PhotosUI
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// The same bounded 3D .cube representation used by the Web version. User data,
/// rather than a bundled commercial film LUT, is persisted in web-config.json.
struct NativeCubeLUT: Equatable, Sendable {
    let size: Int
    let min: [Float]
    let max: [Float]
    /// Red changes fastest, then green, then blue. Each entry contains RGB.
    let colors: [Float]
    let title: String
    static let maximumFileBytes = 5_000_000

    init(text: String) throws {
        guard text.utf8.count <= Self.maximumFileBytes else { throw NativeError.message("LUT は 5 MB 以下で選んでください。") }
        var dimension: Int?
        var minimum: [Float]?
        var maximum: [Float]?
        var values: [Float] = []
        var name = ""
        var hasColors = false
        for raw in text.replacingOccurrences(of: "\u{FEFF}", with: "").split(whereSeparator: \.isNewline) {
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0].trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard let first = parts.first else { continue }
            if first == "TITLE" {
                guard !hasColors, name.isEmpty else { throw Self.invalid }
                name = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                guard name.utf16.count <= 200 else { throw Self.invalid }
            } else if first == "LUT_3D_SIZE" {
                guard !hasColors, dimension == nil, parts.count == 2, let value = Int(parts[1]), (2...33).contains(value) else { throw NativeError.message("LUT のサイズは 2〜33 に対応しています。") }
                dimension = value
                values.reserveCapacity(value * value * value * 3)
            } else if first == "DOMAIN_MIN" || first == "DOMAIN_MAX" {
                guard !hasColors, parts.count == 4 else { throw Self.invalid }
                let components = try Self.numbers(Array(parts.dropFirst()))
                if first == "DOMAIN_MIN" { guard minimum == nil else { throw Self.invalid }; minimum = components }
                else { guard maximum == nil else { throw Self.invalid }; maximum = components }
            } else {
                guard let size = dimension, parts.count == 3, values.count < size * size * size * 3 else { throw Self.invalid }
                values.append(contentsOf: try Self.numbers(parts)); hasColors = true
            }
        }
        guard let size = dimension, values.count == size * size * size * 3 else { throw Self.invalid }
        let lower = minimum ?? [0, 0, 0], upper = maximum ?? [1, 1, 1]
        try Self.validateDomain(lower, upper)
        self.size = size; self.min = lower; self.max = upper; self.colors = values; self.title = name
    }
    init(json: [String: Any]) throws {
        guard let number = nativeNumber(json["size"]), number.rounded(.towardZero) == number, (2...33).contains(number),
              let rows = json["colors"] as? [[Any]], rows.count == Int(number) * Int(number) * Int(number),
              let rawMin = json["min"] as? [Any], rawMin.count == 3,
              let rawMax = json["max"] as? [Any], rawMax.count == 3 else { throw Self.invalid }
        func component(_ value: Any) throws -> Float {
            guard let value = nativeNumber(value), Float(value).isFinite else { throw Self.invalid }; return Float(value)
        }
        let lower = try rawMin.map(component), upper = try rawMax.map(component)
        try Self.validateDomain(lower, upper)
        var values: [Float] = []; values.reserveCapacity(rows.count * 3)
        for row in rows { guard row.count == 3 else { throw Self.invalid }; values.append(contentsOf: try row.map(component)) }
        self.size = Int(number); self.min = lower; self.max = upper; self.colors = values; self.title = ""
    }
    var json: [String: Any] {
        ["size": size, "min": min.map(Double.init), "max": max.map(Double.init),
         "colors": stride(from: 0, to: colors.count, by: 3).map { [Double(colors[$0]), Double(colors[$0 + 1]), Double(colors[$0 + 2])] }]
    }
    static func read(_ url: URL) throws -> NativeCubeLUT {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let metadata = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard metadata.isRegularFile != false, (metadata.fileSize ?? 0) <= maximumFileBytes else { throw NativeError.message("LUT は 5 MB 以下で選んでください。") }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= maximumFileBytes, let text = String(data: data, encoding: .utf8) else { throw Self.invalid }
        return try NativeCubeLUT(text: text)
    }
    private static var invalid: NativeError { .message("3D .cube のデータが不正です。サイズ 2〜33、RGB の 3 列に対応しています。") }
    private static func numbers(_ parts: [Substring]) throws -> [Float] {
        try parts.map { guard let value = Float($0), value.isFinite else { throw invalid }; return value }
    }
    private static func validateDomain(_ lower: [Float], _ upper: [Float]) throws {
        guard zip(lower, upper).allSatisfy({ low, high in
            let span = high - low
            return low.isFinite && high.isFinite && span.isFinite && span > 0 && (1 / span).isFinite
        }) else { throw invalid }
    }
}

struct NativePhotoFilm: Identifiable, Sendable {
    let id: String
    let title: String
}
enum NativePhotoEffects {
    static let films = [
        NativePhotoFilm(id: "none", title: "そのまま"), NativePhotoFilm(id: "sepia(.65) saturate(.7)", title: "あたたか"),
        NativePhotoFilm(id: "grayscale(1)", title: "モノクロ"), NativePhotoFilm(id: "saturate(.65) contrast(.9)", title: "やわらか"), NativePhotoFilm(id: "custom", title: "自分の LUT")
    ]
    static func cube(_ config: [String: Any]) -> NativeCubeLUT? {
        (config["lut"] as? [String: Any]).flatMap { try? NativeCubeLUT(json: $0) }
    }
    static func film(_ config: [String: Any]) -> String {
        let value = config["cameraFilm"] as? String ?? "none"
        return films.contains(where: { $0.id == value }) && (value != "custom" || cube(config) != nil) ? value : "none"
    }
    static func intensity(_ config: [String: Any]) -> Double { Swift.min(1, Swift.max(0, nativeNumber(config["cameraFilmIntensity"]) ?? 1)) }
    private static var colorSpace: CGColorSpace { CGColorSpace(name: CGColorSpace.sRGB)! }
    /// Standard-photo RGB values and .cube samples are processed in sRGB. The
    /// undocumented official film transforms are not represented as these presets.
    private static func context() -> CIContext {
        CIContext(options: [.workingColorSpace: colorSpace, .outputColorSpace: colorSpace, .cacheIntermediates: false])
    }
    static func jpeg(_ data: Data, film: String, lut: NativeCubeLUT?, intensity: Double) throws -> Data {
        guard film != "none", intensity > 0 else { return data }
        guard let source = CIImage(data: data, options: [.applyOrientationProperty: true]) else { throw NativeError.message("写真を読み取れませんでした。") }
        let output = try filtered(source, film: film, lut: lut, intensity: intensity)
        guard let image = context().createCGImage(output, from: source.extent, format: .RGBA8, colorSpace: colorSpace),
              let bytes = CFDataCreateMutable(kCFAllocatorDefault, 0),
              let destination = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil) else { throw NativeError.message("写真の色を調整できませんでした。") }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.83] as CFDictionary)
        guard CGImageDestinationFinalize(destination), CFDataGetLength(bytes) <= 3_500_000 else { throw NativeError.message("写真が大きすぎます。別の写真でお試しください。") }
        return bytes as Data
    }
    private static func filtered(_ source: CIImage, film: String, lut: NativeCubeLUT?, intensity: Double) throws -> CIImage {
        var result: CIImage
        switch film {
        case "none": return source
        case "custom":
            guard let lut else { throw NativeError.message("自分の LUT を読み込んでください。") }
            let scales = zip(lut.min, lut.max).map { CGFloat(1 / ($1 - $0)) }
            let offsets = zip(lut.min, scales).map { -CGFloat($0) * $1 }
            let normalized = source.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: scales[0], y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: scales[1], z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: scales[2], w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: offsets[0], y: offsets[1], z: offsets[2], w: 0)
            ]).applyingFilter("CIColorClamp", parameters: ["inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0), "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)])
            var rgba: [Float] = []; rgba.reserveCapacity(lut.size * lut.size * lut.size * 4)
            for i in stride(from: 0, to: lut.colors.count, by: 3) {
                rgba.append(Swift.min(1, Swift.max(0, lut.colors[i]))); rgba.append(Swift.min(1, Swift.max(0, lut.colors[i + 1]))); rgba.append(Swift.min(1, Swift.max(0, lut.colors[i + 2]))); rgba.append(1)
            }
            let bytes = rgba.withUnsafeBytes { Data($0) }
            guard let filter = CIFilter(name: "CIColorCubeWithColorSpace", parameters: [kCIInputImageKey: normalized, "inputCubeDimension": lut.size, "inputCubeData": bytes, "inputColorSpace": colorSpace]), let output = filter.outputImage else { throw NativeError.message("この LUT を適用できませんでした。") }
            result = output
        case "grayscale(1)": result = source.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        case "sepia(.65) saturate(.7)": result = source.applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: 0.65]).applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.7])
        case "saturate(.65) contrast(.9)": result = source.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.65, kCIInputContrastKey: 0.9])
        default: throw NativeError.message("このフィルムは使えません。")
        }
        let amount = intensity.isFinite ? Swift.min(1, Swift.max(0, intensity)) : 1
        if amount < 1 { result = source.applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: result, kCIInputTimeKey: amount]) }
        return result.cropped(to: source.extent)
    }
    /// A locally generated color chart avoids using third-party sample photos.
    static func sampleJPEG() throws -> Data {
        let width = 400, height = 240
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            let index = (y * width + x) * 4
            bytes[index] = UInt8(x * 255 / (width - 1)); bytes[index + 1] = UInt8(y * 255 / (height - 1)); bytes[index + 2] = UInt8((x / 80 % 2 == 0) ? 160 : 60)
        } }
        let data = bytes.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData), let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent), let result = UIImage(cgImage: image).jpegData(compressionQuality: 0.9) else { throw NativeError.message("色見本を作成できませんでした。") }
        return result
    }
    #if DEBUG
    static func selfTest() throws -> Bool {
        let identity = "TITLE \"Identity\"\nLUT_3D_SIZE 2\n0 0 0\n1 0 0\n0 1 0\n1 1 0\n0 0 1\n1 0 1\n0 1 1\n1 1 1\n"
        let parsed = try NativeCubeLUT(text: identity)
        guard parsed.size == 2, parsed.colors[3] == 1, parsed.colors[4] == 0, (try NativeCubeLUT(json: parsed.json)).colors == parsed.colors else { throw NativeError.message("LUT order or backup compatibility failed.") }
        for bad in [identity + "1 1 1\n", identity.replacingOccurrences(of: "1 1 1\n", with: ""), identity.replacingOccurrences(of: "LUT_3D_SIZE 2", with: "LUT_3D_SIZE 34"), identity.replacingOccurrences(of: "0 0 0\n", with: "nan 0 0\n"), "DOMAIN_MIN 1 0 0\nDOMAIN_MAX 0 1 1\n" + identity, "LUT_3D_SIZE 2\n" + identity] {
            do { _ = try NativeCubeLUT(text: bad) } catch { continue }; throw NativeError.message("Invalid LUT passed validation.")
        }
        var malformed = parsed.json; malformed["size"] = true
        do { _ = try NativeCubeLUT(json: malformed); throw NativeError.message("Boolean LUT size passed validation.") } catch NativeError.message(let message) where message == "Boolean LUT size passed validation." { throw NativeError.message(message) } catch {}
        let source = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        var swap = parsed.json; swap["colors"] = stride(from: 0, to: parsed.colors.count, by: 3).map { [Double(parsed.colors[$0 + 2]), Double(parsed.colors[$0 + 1]), Double(parsed.colors[$0])] }
        let result = try filtered(source, film: "custom", lut: NativeCubeLUT(json: swap), intensity: 1)
        var pixel = [UInt8](repeating: 0, count: 4)
        context().render(result, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: colorSpace)
        guard pixel[0] < 5, pixel[1] < 5, pixel[2] > 250 else { throw NativeError.message("Core Image LUT channel order failed.") }
        let sample = try sampleJPEG()
        guard try jpeg(sample, film: "none", lut: nil, intensity: 1) == sample,
              !(try jpeg(sample, film: "custom", lut: parsed, intensity: 0.5)).isEmpty else { throw NativeError.message("Photo filtering failed.") }
        return true
    }
    #endif
}

@MainActor struct NativeLUTView: View {
    @ObservedObject var model: NativeAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var loading = false
    @State private var photoItem: PhotosPickerItem?
    @State private var source: Data?
    @State private var preview: Data?
    @State private var revision = UUID()
    @State private var film = "none"
    @State private var intensity = 1.0
    @State private var original = false
    @State private var removing = false
    @State private var failure: String?
    @State private var storedCube: NativeCubeLUT?
    private var lut: NativeCubeLUT? { storedCube }
    private var renderKey: String { revision.uuidString + film + String(intensity) + String(original) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let bytes = original ? source : (preview ?? source), let image = UIImage(data: bytes) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 260).listRowInsets(EdgeInsets())
                    } else { ProgressView().frame(maxWidth: .infinity, minHeight: 180) }
                    PhotosPicker(selection: $photoItem, matching: .images) { Label("写真で試す", systemImage: "photo") }.disabled(loading)
                    Toggle("元の写真と比べる", isOn: $original)
                } header: { Text("プレビュー") } footer: { Text("最初は端末内で作った色見本を表示します。選んだ写真はこの画面のプレビューにだけ使います。") }
                Section("フィルム") {
                    Picker("フィルム", selection: $film) {
                        ForEach(NativePhotoEffects.films.filter { $0.id != "custom" || lut != nil }, id: \.id) { Text($0.title).tag($0.id) }
                    }
                    HStack { Text("強さ"); Spacer(); Text("\(Int(intensity * 100)) %").foregroundStyle(.secondary).monospacedDigit() }
                    Slider(value: $intensity, in: 0...1, step: 0.05, onEditingChanged: { editing in if !editing { persistChoices() } }).disabled(film == "none").accessibilityLabel("フィルムの強さ")
                }
                Section {
                    if let lut {
                        LabeledContent("名前", value: model.config["lutName"] as? String ?? "自分の LUT")
                        LabeledContent("サイズ", value: "\(lut.size) × \(lut.size) × \(lut.size)")
                        Button("LUT を削除", role: .destructive) { removing = true }
                    }
                    Button { importing = true } label: { Label(".cube を読み込む", systemImage: "square.and.arrow.down") }.disabled(loading)
                } header: { Text("自分の LUT") } footer: { Text("サイズ 2〜33、5 MB 以下の 3D .cube に対応。写真の取り込み時に適用します。動画の色調整には未対応です。元のライブラリの写真は変更しません。") }
                if loading { ProgressView("準備しています…") }
                if let failure { Text(failure).foregroundStyle(.red) }
            }.navigationTitle("LUT").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } } }
        }.fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "cube") ?? .plainText, .plainText], allowsMultipleSelection: false) { result in
            switch result { case .success(let urls): if let url = urls.first { Task { await importCube(url) } }; case .failure(let error): failure = error.localizedDescription }
        }.confirmationDialog("自分の LUT を削除しますか？", isPresented: $removing, titleVisibility: .visible) {
            Button("LUT を削除", role: .destructive) {
                var next = model.config; next.removeValue(forKey: "lut"); next.removeValue(forKey: "lutName"); if film == "custom" { next["cameraFilm"] = "none" }
                model.saveConfig(next)
                if NativePhotoEffects.cube(model.config) == nil { storedCube = nil; film = NativePhotoEffects.film(model.config); revision = UUID() }
                else { failure = "LUT を削除できませんでした。もう一度お試しください。" }
            }
        }.task {
            storedCube = NativePhotoEffects.cube(model.config); film = NativePhotoEffects.film(model.config); intensity = NativePhotoEffects.intensity(model.config)
            do { if source == nil { source = try NativePhotoEffects.sampleJPEG(); revision = UUID() } } catch { failure = error.localizedDescription }
        }.task(id: renderKey) { await renderPreview() }
            .onChange(of: film) { _, _ in persistChoices() }
            .onChange(of: photoItem) { _, item in guard let item else { return }; Task { await loadPhoto(item) } }
    }
    private func persistChoices() {
        var next = model.config; next["cameraFilm"] = film; next["cameraFilmIntensity"] = intensity; model.saveConfig(next)
        if NativePhotoEffects.film(model.config) != film || NativePhotoEffects.intensity(model.config) != intensity { failure = "フィルムの設定を保存できませんでした。" }
    }
    private func importCube(_ url: URL) async {
        loading = true; failure = nil; defer { loading = false }
        do {
            let cube = try await Task.detached(priority: .userInitiated) { try NativeCubeLUT.read(url) }.value
            var next = model.config; next["lut"] = cube.json; next["lutName"] = cube.title.isEmpty ? String(url.deletingPathExtension().lastPathComponent.prefix(200)) : cube.title; next["cameraFilm"] = "custom"; next["cameraFilmIntensity"] = intensity
            model.saveConfig(next)
            guard let saved = NativePhotoEffects.cube(model.config), saved.colors == cube.colors, saved.min == cube.min, saved.max == cube.max, saved.size == cube.size else { throw NativeError.message("LUT を保存できませんでした。元の設定を残しています。") }
            storedCube = saved; film = "custom"; revision = UUID()
        } catch { failure = error.localizedDescription }
    }
    private func loadPhoto(_ item: PhotosPickerItem) async {
        loading = true; failure = nil; defer { loading = false; photoItem = nil }
        do {
            guard let bytes = try await item.loadTransferable(type: Data.self), bytes.count <= 40_000_000 else { throw NativeError.message("40 MB 以下の写真を選んでください。") }
            let data = try await Task.detached(priority: .userInitiated) { try nativeLUTPreviewPhoto(bytes) }.value
            source = data; preview = nil; revision = UUID()
        } catch { failure = error.localizedDescription }
    }
    private func renderPreview() async {
        guard let source else { return }; if original { return }
        let selected = film, amount = intensity, cube = lut
        do {
            try await Task.sleep(nanoseconds: 120_000_000)
            let result = try await Task.detached(priority: .userInitiated) { try NativePhotoEffects.jpeg(source, film: selected, lut: cube, intensity: amount) }.value
            try Task.checkCancellation(); preview = result
        } catch is CancellationError {} catch { if !Task.isCancelled { failure = error.localizedDescription } }
    }
}

private func nativeLUTPreviewPhoto(_ bytes: Data) throws -> Data {
    guard let source = CGImageSourceCreateWithData(bytes as CFData, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1000, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary), let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) else { throw NativeError.message("写真を読み取れませんでした。") }
    return data
}
