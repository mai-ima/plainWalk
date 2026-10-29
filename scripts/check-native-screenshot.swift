import Foundation
import Vision

// This runs only on the macOS CI screenshot artifact, not on users' photos.
do {
    guard CommandLine.arguments.count == 2 else {
        throw NSError(domain: "PlainWalkScreenshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "Pass the native developer screenshot path."])
    }
    let url = URL(fileURLWithPath: CommandLine.arguments[1])
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ja-JP", "en-US"]
    request.usesLanguageCorrection = false
    try VNImageRequestHandler(url: url).perform([request])
    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        .joined().filter { !$0.isWhitespace }
    guard text.contains("実機検証") else {
        throw NSError(domain: "PlainWalkScreenshot", code: 2, userInfo: [NSLocalizedDescriptionKey: "The screenshot does not show the native diagnostic screen title."])
    }
    print("Native diagnostic screen title verified in the Simulator screenshot.")
} catch {
    fputs(error.localizedDescription + "\n", stderr)
    exit(1)
}
