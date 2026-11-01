import Foundation
import Vision

// One process verifies an entire group; this never scans users' photos.
do {
    guard CommandLine.arguments.count == 2 else { throw NSError(domain:"CaptureOCR",code:1) }
    let file=URL(fileURLWithPath:CommandLine.arguments[1])
    var manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as! [String:Any]
    var screens=manifest["screens"] as! [[String:Any]]
    var failures=[String]()
    func normalized(_ text:String)->String {
        text.folding(options:[.widthInsensitive,.caseInsensitive],locale:Locale(identifier:"ja_JP"))
            .filter{!$0.isWhitespace}
    }
    for index in screens.indices {
        guard screens[index]["status"] as? String == "captured",let path=screens[index]["path"] as? String else {continue}
        let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate
        request.recognitionLanguages=["ja-JP","en-US"];request.usesLanguageCorrection=false
        try VNImageRequestHandler(url:file.deletingLastPathComponent().appendingPathComponent(path)).perform([request])
        let words=(request.results ?? []).compactMap{$0.topCandidates(1).first?.string}
        let text=normalized(words.joined())
        let expected=(screens[index]["expectedText"] as? String ?? "").split(separator:"|").map{normalized(String($0))}
        let passed = !text.isEmpty && (expected.isEmpty || expected.contains(where:{text.contains($0)}))
        screens[index]["recognizedText"]=words
        screens[index]["textVerified"]=passed
        if !passed {failures.append(screens[index]["key"] as? String ?? path)}
    }
    manifest["screens"]=screens
    manifest["complete"]=(manifest["complete"] as? Bool == true) && failures.isEmpty
    try JSONSerialization.data(withJSONObject:manifest,options:[.sortedKeys,.prettyPrinted]).write(to:file,options:.atomic)
    guard failures.isEmpty else {
        throw NSError(domain:"CaptureOCR",code:2,userInfo:[NSLocalizedDescriptionKey:"Screen text not verified: "+failures.joined(separator:", ")])
    }
    print("Native screen text verified for \(screens.count) captures.")
} catch { fputs(error.localizedDescription+"\n",stderr);exit(1) }
