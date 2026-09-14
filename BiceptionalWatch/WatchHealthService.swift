import Foundation
import HealthKit
import Observation

/// Watch-side HealthKit: live HR, active energy, and HKWorkoutSession.
/// Full Recovery math stays on iPhone; the wrist is for starting/ending work
/// and feeling strain as it accumulates.
@Observable
@MainActor
final class WatchHealthService: NSObject {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startDate: Date?

    var currentHeartRate: Double?
    var activeCalories: Double = 0
    var liveStrain: Double = 0
    var isWorkoutRunning = false
    var statusText = String(localized: "Connect Apple Watch to Health to stream heart rate.")
    var elapsed: Duration = .seconds(0)

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKObjectType.workoutType()
        ]
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)]
        try? await store.requestAuthorization(toShare: share, read: read)
        statusText = String(localized: "Health authorized on watch.")
        await refreshSnapshot()
    }

    func refreshSnapshot() async {
        let start = Calendar.current.startOfDay(for: .now)
        let energyType = HKQuantityType(.activeEnergyBurned)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let query = HKStatisticsQuery(quantityType: energyType, quantitySamplePredicate: predicate, options: .cumulativeSum) { [weak self] _, stats, _ in
                let value = stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                Task { @MainActor in
                    self?.activeCalories = value
                    self?.liveStrain = min(21, value / 40)
                    continuation.resume()
                }
            }
            self.store.execute(query)
        }
    }

    func startWorkout() async {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            startDate = .now
            session.startActivity(with: .now)
            try await builder.beginCollection(at: .now)
            isWorkoutRunning = true
        } catch {
            statusText = error.localizedDescription
        }
    }

    func endWorkout() async {
        session?.end()
        do {
            try await builder?.endCollection(at: .now)
            _ = try await builder?.finishWorkout()
        } catch {
            statusText = error.localizedDescription
        }
        isWorkoutRunning = false
        session = nil
        builder = nil
    }
}

extension WatchHealthService: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            isWorkoutRunning = (toState == .running)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            statusText = error.localizedDescription
            isWorkoutRunning = false
        }
    }
}

extension WatchHealthService: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            if let hr = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity() {
                currentHeartRate = hr.doubleValue(for: .count().unitDivided(by: .minute()))
            }
            if let energy = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity() {
                activeCalories = energy.doubleValue(for: .kilocalorie())
                liveStrain = min(21, activeCalories / 40)
            }
            if let startDate {
                elapsed = Duration.seconds(Int64(Date.now.timeIntervalSince(startDate)))
            }
        }
    }
}
