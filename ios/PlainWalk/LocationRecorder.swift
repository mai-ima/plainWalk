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

    override init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PlainWalk", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storeURL = folder.appendingPathComponent("active-session.json")
        super.init()
        if let bytes = try? Data(contentsOf: storeURL), var restored = try? JSONDecoder().decode(NativeSession.self, from: bytes) {
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
        if let session { try JSONEncoder().encode(session).write(to: storeURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        else if FileManager.default.fileExists(atPath: storeURL.path) { try FileManager.default.removeItem(at: storeURL) }
    }
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
                do { try persist() }
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
