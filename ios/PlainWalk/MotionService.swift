import CoreMotion
import Foundation

@MainActor final class MotionService {
    private let activity = CMMotionActivityManager()
    private let pedometer = CMPedometer()
    private var running = false
    private var generation = 0
    private(set) var mode = "walking"
    func start() {
        guard !running, CMMotionActivityManager.isActivityAvailable() else { return }
        let status = CMMotionActivityManager.authorizationStatus()
        guard status != .denied, status != .restricted else { return }
        running = true
        generation += 1
        let activeGeneration = generation
        mode = "walking"
        activity.startActivityUpdates(to: .main) { [weak self] update in
            guard let update else { return }
            // Capture the value before crossing to the actor, not the Core Motion object.
            let mode: String?
            if update.automotive { mode = "vehicle" }
            else if update.cycling { mode = "cycling" }
            else if update.running { mode = "running" }
            else if update.walking { mode = "walking" }
            else { mode = nil }
            Task { @MainActor [weak self] in
                guard let self, self.running, self.generation == activeGeneration, let mode else { return }
                self.mode = mode
            }
        }
    }
    func stop() {
        guard running else { return }
        activity.stopActivityUpdates()
        running = false
        mode = "walking"
    }
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
