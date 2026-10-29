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
    var json: [String: Any] {
        ["lat": lat, "lon": lon, "t": t, "accuracy": accuracy, "seq": seq,
         "gap": gap, "mode": mode ?? "walking", "heading": heading ?? 0]
    }
}

struct NativeSession: Codable {
    var id: String
    var start: Double
    var points: [RecordedPoint] = []
    var recording = false
    var distance: Double = 0
    var nextGap = false
    var json: [String: Any] {
        ["id": id, "start": start, "points": points.map(\.json),
         "recording": recording, "distance": distance]
    }
}

private struct LocationJournalEntry: Codable {
    var sessionID: String
    var point: RecordedPoint
}

@MainActor final class LocationRecorder: NSObject, @preconcurrency CLLocationManagerDelegate, @preconcurrency ObservableObject {
    let manager = CLLocationManager()
    let motion = MotionService()
    let objectWillChange = ObservableObjectPublisher()
    // In-place mutation avoids repeatedly copying an entire long route through @Published.
    private(set) var session: NativeSession?
    private(set) var recoveryIssue: String?
    var onPoint: ((RecordedPoint, String?) -> Void)?
    var onError: ((String) -> Void)?
    var onHeading: ((Double) -> Void)?
    var onSession: ((NativeSession?) -> Void)?
    private var heading: Double = 0
    private var interruptionSent = false
    private var recordingRequested = false
    private var recordingBoundary: Double?
    private var locating = false
    private var unreadableCheckpoint = false
    private let storeURL: URL
    private let journalURL: URL
    private var lastJournalSync: Date = .distantPast

    init(storageDirectory: URL? = nil) {
        let folder = storageDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PlainWalk", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storeURL = folder.appendingPathComponent("active-session.json")
        journalURL = folder.appendingPathComponent("active-session.journal")
        super.init()
        restore()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        manager.headingFilter = 5
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    private static func valid(_ point: RecordedPoint) -> Bool {
        point.lat.isFinite && point.lon.isFinite && point.t.isFinite && point.accuracy.isFinite &&
        abs(point.lat) <= 85 && abs(point.lon) <= 180 && point.accuracy >= 0 && point.seq > 0
    }

    private func restore() {
        let hasCheckpoint = FileManager.default.fileExists(atPath: storeURL.path)
        var restored: NativeSession?
        if let bytes = try? Data(contentsOf: storeURL) {
            restored = try? JSONDecoder().decode(NativeSession.self, from: bytes)
        }
        if let candidate = restored, candidate.id.isEmpty || !candidate.start.isFinite { restored = nil }
        var entries: [LocationJournalEntry] = []
        if let bytes = try? Data(contentsOf: journalURL, options: .mappedIfSafe) {
            // A partial last record must not hide the complete records before it.
            entries = bytes.split(separator: 10).compactMap {
                try? JSONDecoder().decode(LocationJournalEntry.self, from: Data($0))
            }.filter { !$0.sessionID.isEmpty && Self.valid($0.point) }
        }
        if restored == nil, let lastID = entries.last?.sessionID,
           let first = entries.first(where: { $0.sessionID == lastID }) {
            restored = NativeSession(id: lastID, start: first.point.t)
            recoveryIssue = "記録のチェックポイントを読めなかったため、位置ジャーナルから復元しました。開始時刻は最初の記録点です。"
        }
        guard var result = restored, !result.id.isEmpty, result.start.isFinite else {
            unreadableCheckpoint = hasCheckpoint
            if hasCheckpoint { recoveryIssue = "中断した記録を読み取れません。元の保存データを残しています。" }
            return
        }
        let savedCount = result.points.count
        var clean: [RecordedPoint] = []
        for point in result.points where Self.valid(point) {
            if let last = clean.last, point.seq <= last.seq || point.t <= last.t { continue }
            clean.append(point)
        }
        result.points = clean
        if savedCount != clean.count { recoveryIssue = "中断した記録の一部を読み取れませんでした。読み取れる記録点を復元しました。" }
        for entry in entries where entry.sessionID == result.id {
            if let last = result.points.last, entry.point.seq <= last.seq || entry.point.t <= last.t { continue }
            result.points.append(entry.point)
        }
        // Recalculate instead of trusting a stale/corrupted cached total.
        result.distance = 0
        for index in result.points.indices.dropFirst() where !result.points[index].gap {
            let a = result.points[index - 1], b = result.points[index]
            result.distance += CLLocation(latitude: a.lat, longitude: a.lon)
                .distance(from: CLLocation(latitude: b.lat, longitude: b.lon))
        }
        result.recording = false
        result.nextGap = true
        session = result
    }

    /// Returns false for a location-only request while a recording is already running.
    @discardableResult private func prepareSession(id: String?, start: Double?, recording: Bool) throws -> Bool {
        if !recording { return !(recordingRequested && session?.recording == true) }
        guard !unreadableCheckpoint else {
            throw NativeError.message(recoveryIssue ?? "保存された記録を読み取れません。")
        }
        guard let id, !id.isEmpty else { throw NativeError.message("記録の識別子がありません。") }
        if let existing = session, existing.id != id {
            throw NativeError.message("中断したさんぽがあります。保存または破棄してから、新しい記録を始めてください。")
        }
        var candidate = session ?? NativeSession(id: id, start: start ?? Date().timeIntervalSince1970 * 1000)
        guard candidate.start.isFinite else { throw NativeError.message("記録の開始時刻が不正です。") }
        candidate.recording = true
        // State and sensors change only after the checkpoint is durable.
        try checkpoint(candidate)
        objectWillChange.send()
        session = candidate
        return true
    }

    /// Migrate a web session once, before native recording takes ownership of future samples.
    func adoptRecoveredSession(id: String, start: Double, points: [RecordedPoint]) throws {
        guard session == nil, !recordingRequested, !unreadableCheckpoint else {
            throw NativeError.message("端末に中断した記録があります。既存の記録を優先して復元します。")
        }
        guard !id.isEmpty, start.isFinite else { throw NativeError.message("復元する記録の識別子・開始時刻が不正です。") }
        var candidate = NativeSession(id: id, start: start)
        for point in points {
            guard Self.valid(point), point.t >= start else { throw NativeError.message("復元する記録点が不正です。元のデータを残しています。") }
            if let last = candidate.points.last {
                guard point.seq > last.seq, point.t > last.t else {
                    throw NativeError.message("復元する記録点の順序が不正です。元のデータを残しています。")
                }
                if !point.gap {
                    candidate.distance += CLLocation(latitude: last.lat, longitude: last.lon)
                        .distance(from: CLLocation(latitude: point.lat, longitude: point.lon))
                }
            }
            candidate.points.append(point)
        }
        candidate.nextGap = true
        try checkpoint(candidate)
        objectWillChange.send()
        session = candidate
        onSession?(session)
    }

    func start(id: String?, start: Double?, recording: Bool) throws {
        let status = manager.authorizationStatus
        guard status != .denied && status != .restricted else {
            throw NativeError.message("位置情報が許可されていません。iPhone の設定から許可してください。")
        }
        let wasRecording = recordingRequested
        let changesRecording = try prepareSession(id: id, start: start, recording: recording)
        if changesRecording { recordingRequested = recording }
        if recording, !wasRecording { recordingBoundary = Date().timeIntervalSince1970 * 1000 }
        interruptionSent = false
        locating = true
        if status == .notDetermined { manager.requestWhenInUseAuthorization() }
        else { beginUpdates() }
        onSession?(session)
    }

    private func beginUpdates() {
        guard locating else { return }
        manager.allowsBackgroundLocationUpdates = recordingRequested
        manager.startUpdatingLocation()
        if recordingRequested { motion.start() }
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    private func stopSensors() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        motion.stop()
        manager.allowsBackgroundLocationUpdates = false
        recordingRequested = false
        recordingBoundary = nil
        locating = false
    }

    func stop(end: Bool) throws {
        stopSensors()
        objectWillChange.send()
        session?.recording = false
        session?.nextGap = true
        do {
            if let paused = session { try checkpoint(paused) }
            if end {
                // The checkpoint keeps all known points recoverable if deletion fails.
                for url in [journalURL, storeURL] where FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                session = nil
                unreadableCheckpoint = false
                recoveryIssue = nil
            }
            onSession?(session)
        } catch {
            // Never expose an empty session when ending could not be persisted.
            onSession?(session)
            throw error
        }
    }

    private func checkpoint(_ candidate: NativeSession) throws {
        try JSONEncoder().encode(candidate).write(to: storeURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        // A crash before this truncation is safe: recovery rejects journal seqs in the checkpoint.
        try Data().write(to: journalURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        lastJournalSync = .distantPast
    }

    private func appendToJournal(_ point: RecordedPoint, sessionID: String) throws {
        if !FileManager.default.fileExists(atPath: journalURL.path) {
            try Data().write(to: journalURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        var bytes = try JSONEncoder().encode(LocationJournalEntry(sessionID: sessionID, point: point))
        bytes.append(10)
        let handle = try FileHandle(forUpdating: journalURL)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        if end > 0 {
            // Separate an interrupted, incomplete final record from this complete one.
            try handle.seek(toOffset: end - 1)
            let last = try handle.read(upToCount: 1)
            try handle.seekToEnd()
            if last?.first != 10 { try handle.write(contentsOf: Data([10])) }
        }
        try handle.write(contentsOf: bytes)
        if Date().timeIntervalSince(lastJournalSync) >= 10 {
            try handle.synchronize()
            lastJournalSync = Date()
        }
    }

    private func storageFailure() {
        stopSensors()
        objectWillChange.send()
        session?.recording = false
        session?.nextGap = true
        onSession?(session)
        onError?("位置記録を保存できないため、一時停止しました。端末の空き容量を確認してください。")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: beginUpdates()
        case .denied, .restricted:
            do { try stop(end: false) }
            catch { onError?("位置情報の権限変更後、記録を保存できませんでした。") }
            onError?("位置情報が許可されていません。iPhone の設定を確認してください。")
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard locating || recordingRequested else { return }
        for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            let age = -location.timestamp.timeIntervalSinceNow
            guard location.horizontalAccuracy.isFinite, location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 60,
                  location.coordinate.latitude.isFinite, location.coordinate.longitude.isFinite,
                  abs(location.coordinate.latitude) <= 85, abs(location.coordinate.longitude) <= 180,
                  age >= -5, age < 120 else { continue }
            var point = RecordedPoint(lat: location.coordinate.latitude, lon: location.coordinate.longitude,
                                      t: location.timestamp.timeIntervalSince1970 * 1000, accuracy: location.horizontalAccuracy,
                                      seq: (session?.points.last?.seq ?? 0) + 1, gap: false)
            if recordingRequested, let sessionID = session?.id {
                // Core Location may immediately deliver a cached pre-start/pre-resume fix.
                let boundary = max(session?.start ?? point.t, recordingBoundary ?? -.infinity)
                guard point.t >= boundary else { continue }
                // Copy scalar metadata only; retaining NativeSession here copies its Array on append.
                let previous = session?.points.last
                point.gap = session?.nextGap ?? true
                point.mode = motion.mode
                point.heading = heading
                var addedDistance = 0.0
                if let previous {
                    let delta = (point.t - previous.t) / 1000
                    let meters = location.distance(from: CLLocation(latitude: previous.lat, longitude: previous.lon))
                    guard delta > 0 else { continue }
                    if delta > 120 { point.gap = true }
                    if !point.gap && (meters < 3 || meters / delta > 45) { continue }
                    if !point.gap { addedDistance = meters }
                }
                // Do not publish or increment the seq until the journal write succeeds.
                do { try appendToJournal(point, sessionID: sessionID) }
                catch { storageFailure(); break }
                objectWillChange.send()
                session?.distance += addedDistance
                session?.points.append(point)
                session?.nextGap = false
                session?.recording = true
                interruptionSent = false
                onPoint?(point, sessionID)
                onSession?(session)
            } else {
                onPoint?(point, nil)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let candidate = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        guard newHeading.headingAccuracy >= 0, candidate.isFinite, candidate >= 0 else { return }
        heading = candidate.truncatingRemainder(dividingBy: 360)
        onHeading?(heading)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard (error as? CLError)?.code != .locationUnknown else { return }
        if (error as? CLError)?.code == .denied {
            do { try stop(end: false) } catch { onError?("位置情報を停止した後、記録を保存できませんでした。") }
        }
        if recordingRequested && !interruptionSent { NotificationService.interruption(); interruptionSent = true }
        onError?(error.localizedDescription)
    }

    #if DEBUG
    static func persistenceSelfTest() throws -> Bool {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("plainwalk-persistence-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = LocationRecorder(storageDirectory: directory)
        first.session = NativeSession(id: "persistence-test", start: Date().addingTimeInterval(-15).timeIntervalSince1970 * 1000)
        first.session?.recording = true
        first.recordingRequested = true
        try first.checkpoint(first.session!)
        let preserved = try first.prepareSession(id: nil, start: nil, recording: false)
        guard !preserved, first.recordingRequested, first.session?.recording == true else {
            throw NativeError.message("Locate-only request changed recording state.")
        }
        do {
            try first.prepareSession(id: "wrong-session", start: nil, recording: true)
            throw NativeError.message("An unrelated session replaced active recording.")
        } catch NativeError.message(let text) where text.hasPrefix("中断したさんぽ") {}
        let base = Date().addingTimeInterval(-10)
        let samples = (0..<3).map { index in
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: 35.68 + Double(index) * 0.0001, longitude: 139.76), altitude: 0,
                       horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: base.addingTimeInterval(Double(index) * 5))
        }
        let stale = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 35.67, longitude: 139.76), altitude: 0,
                               horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date().addingTimeInterval(-20))
        let future = CLLocation(coordinate: stale.coordinate, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                                timestamp: Date().addingTimeInterval(60))
        first.locationManager(first.manager, didUpdateLocations: [stale, future])
        guard first.session?.points.isEmpty == true else { throw NativeError.message("A pre-start or future GPS fix entered the trail.") }
        first.locationManager(first.manager, didUpdateLocations: samples)
        first.recordingBoundary = Date().addingTimeInterval(2).timeIntervalSince1970 * 1000
        first.locationManager(first.manager, didUpdateLocations: [
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: 35.69, longitude: 139.76), altitude: 0,
                       horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date().addingTimeInterval(1))
        ])
        guard first.session?.points.count == 3 else { throw NativeError.message("A cached paused-interval fix entered the resumed trail.") }
        first.recordingBoundary = nil
        let handle = try FileHandle(forWritingTo: first.journalURL)
        _ = try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"incomplete\":".utf8))
        try handle.close()
        let restored = LocationRecorder(storageDirectory: directory)
        guard restored.session?.points.count == 3, (restored.session?.distance ?? 0) > 20, restored.session?.recording == false else {
            throw NativeError.message("Recorder journal restoration failed.")
        }
        try restored.stop(end: false)
        let checkpointed = LocationRecorder(storageDirectory: directory)
        guard checkpointed.session?.points.count == 3 else { throw NativeError.message("Recorder checkpoint duplicated samples.") }
        // A corrupt checkpoint must not hide intact append-only journal data.
        let journalDirectory = directory.appendingPathComponent("journal-recovery", isDirectory: true)
        try FileManager.default.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
        try Data("invalid-checkpoint".utf8).write(to: journalDirectory.appendingPathComponent("active-session.json"))
        var journal = Data()
        for point in first.session?.points ?? [] {
            journal.append(try JSONEncoder().encode(LocationJournalEntry(sessionID: "persistence-test", point: point)))
            journal.append(10)
        }
        try journal.write(to: journalDirectory.appendingPathComponent("active-session.journal"))
        let journalRecovered = LocationRecorder(storageDirectory: journalDirectory)
        guard journalRecovered.session?.points.count == 3, journalRecovered.recoveryIssue != nil else {
            throw NativeError.message("Intact journal data was not recovered after checkpoint corruption.")
        }
        let migrationDirectory = directory.appendingPathComponent("migration", isDirectory: true)
        let migrated = LocationRecorder(storageDirectory: migrationDirectory)
        try migrated.adoptRecoveredSession(id: "migrated-web", start: first.session!.start, points: first.session!.points)
        let reloadedMigration = LocationRecorder(storageDirectory: migrationDirectory)
        guard reloadedMigration.session?.points.count == 3, reloadedMigration.session?.recording == false,
              reloadedMigration.session?.nextGap == true else {
            throw NativeError.message("Migrated web points were not durably recovered as a paused native session.")
        }
        let interrupted = LocationRecorder(storageDirectory: directory.appendingPathComponent("gap", isDirectory: true))
        let gapStart = Date().addingTimeInterval(-300).timeIntervalSince1970 * 1000
        interrupted.session = NativeSession(id: "gap", start: gapStart)
        interrupted.session?.points = [RecordedPoint(lat: 35.0, lon: 139.0, t: gapStart, accuracy: 5, seq: 1, gap: false)]
        interrupted.session?.recording = true
        interrupted.recordingRequested = true
        interrupted.locationManager(interrupted.manager, didUpdateLocations: [samples[2]])
        guard interrupted.session?.points.count == 2, interrupted.session?.points.last?.gap == true, interrupted.session?.distance == 0 else {
            throw NativeError.message("A long GPS outage was connected as walked distance.")
        }
        // Checkpoint failure must not consume an in-memory point or continue recording.
        let failed = LocationRecorder(storageDirectory: directory.appendingPathComponent("failure", isDirectory: true))
        failed.session = NativeSession(id: "io-failure", start: base.timeIntervalSince1970 * 1000)
        failed.session?.recording = true
        failed.recordingRequested = true
        try FileManager.default.createDirectory(at: failed.journalURL, withIntermediateDirectories: true)
        failed.locationManager(failed.manager, didUpdateLocations: [samples[0]])
        guard failed.session?.points.isEmpty == true, failed.session?.recording == false else {
            throw NativeError.message("Failed journal writes published an unpersisted point.")
        }
        try checkpointed.stop(end: true)
        return true
    }
    #endif
}

enum NativeError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
