import Foundation
import CoreLocation
import Combine

struct RecordedPoint: Codable {
    var lat: Double
    var lon: Double
    var t: Double
    var accuracy: Double
    var seq: Int
    var gap: Bool
    var mode: String? = nil
    var heading: Double? = nil
    var json: [String: Any] { ["lat": lat, "lon": lon, "t": t, "accuracy": accuracy, "seq": seq, "gap": gap, "mode": mode ?? "walking", "heading": heading ?? 0] }
}
struct NativeSession: Codable {
    var id: String
    var start: Double
    var points: [RecordedPoint] = []
    var recording = false
    var distance: Double = 0
    var nextGap = false
    var json: [String: Any] { ["id": id, "start": start, "points": points.map(\.json), "recording": recording, "distance": distance] }
}

private struct LocationJournalEntry: Codable { var sessionID: String; var point: RecordedPoint }

@MainActor final class LocationRecorder: NSObject, @preconcurrency CLLocationManagerDelegate, ObservableObject {
    let manager = CLLocationManager()
    let motion = MotionService()
    private var heading: Double = 0
    private var interruptionSent = false
    @Published private(set) var session: NativeSession?
    var onPoint: ((RecordedPoint, String?) -> Void)?
    var onError: ((String) -> Void)?
    var onSession: ((NativeSession?) -> Void)?
    private var recordingRequested = false
    private var locating = false
    private let storeURL: URL
    private let journalURL: URL
    private var lastJournalSync: Date = .distantPast

    init(storageDirectory: URL? = nil) {
        let folder = storageDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PlainWalk", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storeURL = folder.appendingPathComponent("active-session.json")
        journalURL = folder.appendingPathComponent("active-session.journal")
        super.init()
        if let bytes = try? Data(contentsOf: storeURL), var restored = try? JSONDecoder().decode(NativeSession.self, from: bytes) {
            if let journal = try? Data(contentsOf: journalURL) {
                for line in journal.split(separator: 10) {
                    guard let entry = try? JSONDecoder().decode(LocationJournalEntry.self, from: Data(line)), entry.sessionID == restored.id, entry.point.seq > (restored.points.last?.seq ?? 0) else { continue }
                    if let last = restored.points.last, !entry.point.gap {
                        restored.distance += CLLocation(latitude: last.lat, longitude: last.lon).distance(from: CLLocation(latitude: entry.point.lat, longitude: entry.point.lon))
                    }
                    restored.points.append(entry.point)
                }
            }
            // An explicit foreground action is required after a process termination.
            restored.recording = false; restored.nextGap = true; session = restored
        }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }
    func start(id: String?, start: Double?, recording: Bool) throws {
        let status = manager.authorizationStatus
        guard status != .denied && status != .restricted else {
            throw NativeError.message("位置情報が許可されていません。iPhone の設定から許可してください。")
        }
        if recording, let id {
            if session?.id != id { session = NativeSession(id: id, start: start ?? Date().timeIntervalSince1970 * 1000) }
            session?.recording = true
            try persist()
        }
        recordingRequested = recording
        interruptionSent = false
        if recording { motion.start() }
        locating = true
        if status == .notDetermined { manager.requestWhenInUseAuthorization() }
        else { beginUpdates() }
        onSession?(session)
    }
    private func beginUpdates() {
        guard locating else { return }
        manager.allowsBackgroundLocationUpdates = recordingRequested
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }
    func stop(end: Bool) throws {
        manager.stopUpdatingLocation(); manager.stopUpdatingHeading(); motion.stop()
        manager.allowsBackgroundLocationUpdates = false
        recordingRequested = false; locating = false
        if end { session = nil }
        else { session?.recording = false; session?.nextGap = true }
        try persist(); onSession?(session)
    }
    private func persist() throws {
        if let session {
            // A checkpoint is written only for start/pause/end/permission changes.
            try JSONEncoder().encode(session).write(to: storeURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try Data().write(to: journalURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } else {
            for url in [storeURL, journalURL] where FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }
    private func appendToJournal(_ point: RecordedPoint, sessionID: String) throws {
        if !FileManager.default.fileExists(atPath: journalURL.path) { try Data().write(to: journalURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        var bytes = try JSONEncoder().encode(LocationJournalEntry(sessionID: sessionID, point: point)); bytes.append(10)
        let handle = try FileHandle(forWritingTo: journalURL)
        defer { try? handle.close() }
        _ = try handle.seekToEnd(); try handle.write(contentsOf: bytes)
        if Date().timeIntervalSince(lastJournalSync) >= 10 { try handle.synchronize(); lastJournalSync = Date() }
    }
    #if DEBUG
    static func persistenceSelfTest() throws -> Bool {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("plainwalk-persistence-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = LocationRecorder(storageDirectory: directory)
        first.session = NativeSession(id: "persistence-test", start: Date().timeIntervalSince1970 * 1000)
        first.recordingRequested = true
        try first.persist()
        let samples = (0..<3).map { index in CLLocation(coordinate: CLLocationCoordinate2D(latitude: 35.68 + Double(index) * 0.0001, longitude: 139.76), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date().addingTimeInterval(Double(index) * 5)) }
        first.locationManager(first.manager, didUpdateLocations: samples)
        let restored = LocationRecorder(storageDirectory: directory)
        guard restored.session?.points.count == 3, (restored.session?.distance ?? 0) > 20, restored.session?.recording == false else { throw NativeError.message("Recorder journal restoration failed.") }
        try restored.stop(end: false)
        let checkpointed = LocationRecorder(storageDirectory: directory)
        guard checkpointed.session?.points.count == 3 else { throw NativeError.message("Recorder checkpoint duplicated samples.") }
        try checkpointed.stop(end: true)
        return true
    }
    #endif
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: beginUpdates()
        case .denied, .restricted:
            manager.stopUpdatingLocation(); recordingRequested = false
            session?.recording = false; try? persist(); onSession?(session)
            onError?("位置情報が許可されていません。iPhone の設定を確認してください。")
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 60,
                  abs(location.coordinate.latitude) <= 85, abs(location.coordinate.longitude) <= 180,
                  abs(location.timestamp.timeIntervalSinceNow) < 120 else { continue }
            var point = RecordedPoint(lat: location.coordinate.latitude, lon: location.coordinate.longitude,
                                      t: location.timestamp.timeIntervalSince1970 * 1000,
                                      accuracy: location.horizontalAccuracy, seq: (session?.points.last?.seq ?? 0) + 1, gap: false)
            if recordingRequested, var next = session {
                point.gap = next.nextGap; point.mode = motion.mode; point.heading = heading
                if let previous = next.points.last {
                    let before = CLLocation(latitude: previous.lat, longitude: previous.lon)
                    let delta = (point.t - previous.t) / 1000
                    let meters = location.distance(from: before)
                    guard delta > 0, meters >= 3 else { continue }
                    if delta > 120 { point.gap = true }
                    if !point.gap && meters / delta > 45 { continue }
                    if !point.gap { next.distance += meters }
                }
                next.points.append(point); next.nextGap = false; next.recording = true
                session = next
                do { try appendToJournal(point, sessionID: next.id) }
                catch { onError?("位置記録を保存できません。端末の空き容量を確認してください。"); continue }
                onPoint?(point, next.id); onSession?(next)
            } else { onPoint?(point, nil) }
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) { heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code != .locationUnknown { if recordingRequested && !interruptionSent { NotificationService.interruption(); interruptionSent = true }; onError?(error.localizedDescription) }
    }
}
enum NativeError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
