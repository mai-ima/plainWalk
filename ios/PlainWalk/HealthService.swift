import Foundation
import HealthKit
import CoreLocation

final class HealthService {
    private let store = HKHealthStore()
    private let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
    func authorize() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw NativeError.message("この端末ではヘルスケアを利用できません。") }
        let types: Set<HKObjectType> = [stepType, HKObjectType.workoutType(), HKSeriesType.workoutRoute(), HKQuantityType.quantityType(forIdentifier: .heartRate)!, HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!]
        try await store.requestAuthorization(toShare: [], read: types)
    }
    func steps() async throws -> Double? {
        try await authorize()
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: .count())) }
            }
            store.execute(query)
        }
    }
    func workouts() async throws -> [[String: Any]] {
        try await authorize()
        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [HKQuery.predicateForWorkouts(with: .walking), HKQuery.predicateForWorkouts(with: .running), HKQuery.predicateForWorkouts(with: .hiking), HKQuery.predicateForWorkouts(with: .cycling)])
        let samples: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 200, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples as? [HKWorkout] ?? []) }
            }
            store.execute(query)
        }
        return samples.map { ["id": $0.uuid.uuidString, "start": $0.startDate.timeIntervalSince1970 * 1000, "end": $0.endDate.timeIntervalSince1970 * 1000, "distance": $0.totalDistance?.doubleValue(for: .meter()) ?? 0, "duration": $0.duration, "kind": $0.workoutActivityType == .cycling ? "cycling" : $0.workoutActivityType == .running ? "running" : "walking"] }
    }
    func route(id: String) async throws -> [[String: Any]] {
        guard let uuid = UUID(uuidString: id) else { throw NativeError.message("ワークアウトの ID が不正です。") }
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            store.execute(HKSampleQuery(sampleType: .workoutType(), predicate: HKQuery.predicateForObject(with: uuid), limit: 1, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples as? [HKWorkout] ?? []) }
            })
        }
        guard let workout = workouts.first else { throw NativeError.message("このワークアウトを読み取れません。共有の許可を確認してください。") }
        let routes: [HKWorkoutRoute] = try await withCheckedThrowingContinuation { continuation in
            store.execute(HKSampleQuery(sampleType: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: workout), limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples as? [HKWorkoutRoute] ?? []) }
            })
        }
        var points: [[String: Any]] = []
        for route in routes {
            let locations: [CLLocation] = try await withCheckedThrowingContinuation { continuation in
                var buffer: [CLLocation] = []; var completed = false
                store.execute(HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                    guard !completed else { return }
                    if let error { completed = true; continuation.resume(throwing: error); return }
                    buffer.append(contentsOf: locations ?? [])
                    if done { completed = true; continuation.resume(returning: buffer) }
                })
            }
            for (index, location) in locations.sorted(by: { $0.timestamp < $1.timestamp }).enumerated() {
                points.append(["lat": location.coordinate.latitude, "lon": location.coordinate.longitude, "t": location.timestamp.timeIntervalSince1970 * 1000, "break": index == 0 && !points.isEmpty])
            }
        }
        return points
    }
}
