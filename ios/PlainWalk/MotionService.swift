import CoreMotion
import Foundation

final class MotionService {
    private let activity = CMMotionActivityManager()
    private let pedometer = CMPedometer()
    var mode = "walking"
    func start() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        activity.startActivityUpdates(to: .main) { [weak self] update in
            guard let update else { return }
            if update.automotive { self?.mode = "vehicle" }
            else if update.cycling { self?.mode = "cycling" }
            else if update.running { self?.mode = "running" }
            else if update.walking { self?.mode = "walking" }
        }
    }
    func stop() { activity.stopActivityUpdates() }
    func steps() async throws -> Double? {
        guard CMPedometer.isStepCountingAvailable() else { throw NativeError.message("この端末では歩数計を利用できません。") }
        let start = Calendar.current.startOfDay(for: Date())
        return try await withCheckedThrowingContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: Date()) { data, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: data?.numberOfSteps.doubleValue) }
            }
        }
    }
}
