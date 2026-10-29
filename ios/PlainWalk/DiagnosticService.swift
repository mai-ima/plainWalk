import Foundation
import UIKit
import CoreLocation
import CoreMotion
import AVFoundation
import UserNotifications

@MainActor enum DiagnosticService {
    private static func locationName(_ status: CLAuthorizationStatus) -> String {
        switch status { case .notDetermined: return "notDetermined"; case .restricted: return "restricted"; case .denied: return "denied"; case .authorizedAlways: return "always"; case .authorizedWhenInUse: return "whenInUse"; @unknown default: return "unknown" }
    }
    private static func mediaName(_ status: AVAuthorizationStatus) -> String {
        switch status { case .notDetermined: return "notDetermined"; case .restricted: return "restricted"; case .denied: return "denied"; case .authorized: return "authorized"; @unknown default: return "unknown" }
    }
    static func snapshot(recorder: LocationRecorder) async -> [String: Any] {
        let notifications = await UNUserNotificationCenter.current().notificationSettings()
        let notificationName: String
        switch notifications.authorizationStatus { case .notDetermined: notificationName = "notDetermined"; case .denied: notificationName = "denied"; case .authorized: notificationName = "authorized"; case .provisional: notificationName = "provisional"; case .ephemeral: notificationName = "ephemeral"; @unknown default: notificationName = "unknown" }
        let motionName: String
        switch CMMotionActivityManager.authorizationStatus() { case .notDetermined: motionName = "notDetermined"; case .restricted: motionName = "restricted"; case .denied: motionName = "denied"; case .authorized: motionName = "authorized"; @unknown default: motionName = "unknown" }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PlainWalk", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let storedBytes = files.reduce(0) { total, file in total + ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        let fileSystem = (try? FileManager.default.attributesOfFileSystem(forPath: folder.deletingLastPathComponent().path)) ?? [:]
        let freeBytes = (fileSystem[.systemFreeSize] as? NSNumber)?.int64Value ?? -1
        let last = recorder.session?.points.last
        #if PLAYGROUNDS
        let flavor = "playgrounds"
        #else
        let flavor = "xcode"
        #endif
        return [
            "flavor": flavor, "systemVersion": UIDevice.current.systemVersion, "deviceFamily": UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone",
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "locationAuthorization": locationName(recorder.manager.authorizationStatus),
            "accuracyAuthorization": recorder.manager.accuracyAuthorization == .fullAccuracy ? "precise" : "reduced",
            "motionAuthorization": motionName, "cameraAuthorization": mediaName(AVCaptureDevice.authorizationStatus(for: .video)),
            "microphoneAuthorization": mediaName(AVCaptureDevice.authorizationStatus(for: .audio)), "notificationAuthorization": notificationName,
            "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled, "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
            "backgroundRefresh": UIApplication.shared.backgroundRefreshStatus.rawValue,
            "backgroundLocation": recorder.manager.allowsBackgroundLocationUpdates,
            "nativeRecording": recorder.session?.recording ?? false, "nativePoints": recorder.session?.points.count ?? 0,
            "lastAccuracy": last.map { $0.accuracy as Any } ?? NSNull(),
            "lastFixAgeMs": last.map { max(0, Date().timeIntervalSince1970 * 1000 - $0.t) as Any } ?? NSNull(),
            "storedBytes": storedBytes, "freeBytes": freeBytes
        ]
    }
    static func storageTest() throws -> [String: Any] {
        let started = Date()
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PlainWalk-Diagnostic-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("probe.json")
        let bytes = Data("{\"probe\":\"plainwalk\"}".utf8)
        try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        guard try Data(contentsOf: file) == bytes else { throw NativeError.message("保存の往復テストで内容が一致しません。") }
        return ["ok": true, "durationMs": Int(Date().timeIntervalSince(started) * 1000)]
    }
}
