import Foundation
import Vision
import CoreImage

struct CutoutService {
    static func cutout(_ bytes: Data) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let handler = VNImageRequestHandler(data: bytes, options: [:])
            let request = VNGenerateForegroundInstanceMaskRequest()
            try handler.perform([request])
            guard let result = request.results?.first, !result.allInstances.isEmpty else {
                throw NativeError.message("切り抜く被写体が見つかりませんでした。別の写真をお試しください。")
            }
            let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
            let image = CIImage(cvPixelBuffer: buffer)
            guard let output = CIContext().pngRepresentation(of: image, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()) else {
                throw NativeError.message("ステッカーを書き出せませんでした。")
            }
            return output
        }.value
    }
}
