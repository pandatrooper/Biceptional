import Foundation
import HealthKit
import Observation
import OSLog

/// Owns HealthKit authorization, reads, writes, and background delivery.
///
/// Xcode setup that cannot be done from code (see README):
/// 1. Signing & Capabilities → HealthKit, with "Background Delivery" checked.
/// 2. Signing & Capabilities → App Groups → `group.com.pandatrooper.Biceptional`.
/// 3. Info.plist already contains `NSHealthShareUsageDescription` and
///    `NSHealthUpdateUsageDescription`. Confirm they survive if you regenerate
///    the Info.plist from build settings.
@Observable
@MainActor
final class HealthKitManager {
    private let store = HKHealthStore()
    private let logger = Logger(subsystem: "com.pandatrooper.Biceptional", category: "HealthKit")

    private(set) var isHealthDataAvailable: Bool
    private(set) var authorizationState: AuthorizationState = .notRequested
    private(set) var lastErrorMessage: String?

    private var observerQueries: [HKObserverQuery] = []
    private var workoutAnchor: HKQueryAnchor?

    /// Fired whenever an observer query reports new samples so scores can refresh.
    var onDataDidChange: (@MainActor () -> Void)?

    enum AuthorizationState: Equatable {
        case notRequested
        case requesting
        case sharingAuthorized
        case sharingDenied
        case unavailable
    }

    init() {
        isHealthDataAvailable = HKHealthStore.isHealthDataAvailable()
        if !isHealthDataAvailable {
            authorizationState = .unavailable
        }
    }

    // MARK: - Types

    /// Read types requested at first launch. Keep this list in sync with README.
    static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRate),
            HKQuantityType(.respiratoryRate),
            HKQuantityType(.oxygenSaturation),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning),
            HKObjectType.workoutType(),
            HKQuantityType(.bodyMass),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.vo2Max),
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryProtein),
            HKQuantityType(.dietaryCarbohydrates),
            HKQuantityType(.dietaryFatTotal),
            HKQuantityType(.dietaryFiber)
        ]
        types.insert(HKSeriesType.workoutRoute())
        return types
    }

    static var shareTypes: Set<HKSampleType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.bodyMass),
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryProtein),
            HKQuantityType(.dietaryCarbohydrates),
            HKQuantityType(.dietaryFatTotal),
            HKQuantityType(.dietaryFiber)
        ]
    }

    private var observerTypes: [HKSampleType] {
        [
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRate),
            HKQuantityType(.respiratoryRate),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.stepCount),
            HKObjectType.workoutType(),
            HKQuantityType(.bodyMass),
            HKQuantityType(.dietaryEnergyConsumed)
        ]
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        guard isHealthDataAvailable else {
            authorizationState = .unavailable
            return
        }
        authorizationState = .requesting
        do {
            try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
            // HealthKit does not reveal read-grant status. A successful prompt
            // plus a later query is the only practical signal.
            UserDefaults.standard.set(true, forKey: "didRequestHealthAuth")
            authorizationState = .sharingAuthorized
            await enableBackgroundDelivery()
            startObserving()
        } catch {
            logger.error("HealthKit authorization failed: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = error.localizedDescription
            authorizationState = .sharingDenied
        }
    }

    /// Call from `App.init` / scene phase `.active` so observer queries are
    /// registered even when the user has already granted access.
    func skipAuthorization() {
        authorizationState = .sharingDenied
    }

    func restoreBackgroundDeliveryIfPossible() async {
        guard isHealthDataAvailable, authorizationState != .unavailable else { return }
        guard UserDefaults.standard.bool(forKey: "didRequestHealthAuth") else { return }
        authorizationState = .sharingAuthorized
        await enableBackgroundDelivery()
        startObserving()
    }

    private func enableBackgroundDelivery() async {
        for type in observerTypes {
            do {
                try await store.enableBackgroundDelivery(for: type, frequency: .hourly)
            } catch {
                logger.warning("Background delivery unavailable for \(type.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func startObserving() {
        stopObserving()
        for type in observerTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, error in
                if error != nil {
                    completionHandler()
                    return
                }
                Task { @MainActor in
                    self?.onDataDidChange?()
                }
                completionHandler()
            }
            store.execute(query)
            observerQueries.append(query)
        }
        logger.info("Started \(self.observerQueries.count, privacy: .public) HealthKit observer queries.")
    }

    private func stopObserving() {
        observerQueries.forEach(store.stop)
        observerQueries.removeAll()
    }

    // MARK: - Reads

    func overnightPhysiology(morning: Date) async -> OvernightPhysiology {
        let window = CalendarDay.overnightWindow(endingOnMorning: morning)
        async let hrv = averageQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), start: window.start, end: window.end)
        async let rhr = mostRecentQuantity(.restingHeartRate, unit: .count().unitDivided(by: .minute()), start: window.start, end: window.end)
        async let rr = averageQuantity(.respiratoryRate, unit: .count().unitDivided(by: .minute()), start: window.start, end: window.end)
        async let spo2 = averageQuantity(.oxygenSaturation, unit: .percent(), start: window.start, end: window.end)
        return OvernightPhysiology(
            hrvSDNN: await hrv,
            restingHeartRate: await rhr,
            respiratoryRate: await rr,
            oxygenSaturation: await spo2
        )
    }

    func baseline(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        endingOn morning: Date,
        days: Int = 30
    ) async -> BaselineStats? {
        let window = CalendarDay.range(endingOn: morning.adding(days: -1), days: days)
        let daily = await dailyAverages(identifier, unit: unit, start: window.start, end: window.end)
        let fallback: Double
        switch identifier {
        case .heartRateVariabilitySDNN: fallback = 10
        case .restingHeartRate: fallback = 5
        case .respiratoryRate: fallback = 1.5
        default: fallback = 1
        }
        return BaselineStats.from(daily.map(\.value), fallbackSD: fallback)
    }

    func sleepNights(endingOn morning: Date, days: Int) async -> [SleepNight] {
        let window = CalendarDay.range(endingOn: morning, days: days + 1)
        let type = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: window.start, end: window.end)
        let samples: [HKCategorySample]
        do {
            samples = try await querySamples(of: type, predicate: predicate)
        } catch {
            logger.error("Sleep query failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
        return Self.groupSleepSamples(samples, endingOn: morning)
    }

    func activityTotals(on day: Date) async -> DailyActivityTotals {
        let start = CalendarDay.start(of: day)
        let end = CalendarDay.end(of: day)
        async let steps = sumQuantity(.stepCount, unit: .count(), start: start, end: end)
        async let distance = sumQuantity(.distanceWalkingRunning, unit: .meter(), start: start, end: end)
        async let active = sumQuantity(.activeEnergyBurned, unit: .kilocalorie(), start: start, end: end)
        async let basal = sumQuantity(.basalEnergyBurned, unit: .kilocalorie(), start: start, end: end)
        async let vo2 = mostRecentQuantity(.vo2Max, unit: HKUnit.literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo).unitMultiplied(by: .minute())), start: start.adding(days: -90), end: end)
        return DailyActivityTotals(
            steps: Int(await steps ?? 0),
            distanceMeters: await distance ?? 0,
            activeEnergyKilocalories: await active ?? 0,
            basalEnergyKilocalories: await basal ?? 0,
            vo2Max: await vo2
        )
    }

    func heartRateSeries(on day: Date) async -> [(date: Date, bpm: Double)] {
        let start = CalendarDay.start(of: day)
        let end = CalendarDay.end(of: day)
        let type = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        do {
            let samples: [HKQuantitySample] = try await querySamples(of: type, predicate: predicate)
            let unit = HKUnit.count().unitDivided(by: .minute())
            return samples.map { ($0.startDate, $0.quantity.doubleValue(for: unit)) }
        } catch {
            logger.error("Heart rate query failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func dietaryDay(on day: Date) async -> DietaryDay? {
        let start = CalendarDay.start(of: day)
        let end = CalendarDay.end(of: day)
        async let energy = sumQuantity(.dietaryEnergyConsumed, unit: .kilocalorie(), start: start, end: end)
        async let protein = sumQuantity(.dietaryProtein, unit: .gram(), start: start, end: end)
        async let carbs = sumQuantity(.dietaryCarbohydrates, unit: .gram(), start: start, end: end)
        async let fat = sumQuantity(.dietaryFatTotal, unit: .gram(), start: start, end: end)
        async let fiber = sumQuantity(.dietaryFiber, unit: .gram(), start: start, end: end)

        let kcal = await energy ?? 0
        let p = await protein ?? 0
        let c = await carbs ?? 0
        let f = await fat ?? 0
        let fi = await fiber ?? 0
        guard kcal > 0 || p > 0 else { return nil }
        return DietaryDay(
            energyKilocalories: kcal,
            proteinGrams: p,
            carbsGrams: c,
            fatGrams: f,
            fiberGrams: fi,
            sourceLabel: String(localized: "Apple Health")
        )
    }

    func recentWorkouts(limit: Int = 200) async -> [HKWorkout] {
        let type = HKObjectType.workoutType()
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        do {
            let found: [HKWorkout] = try await querySamples(of: type, predicate: nil, limit: limit, sortDescriptors: [sort])
            return found
        } catch {
            logger.error("Workout query failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func newWorkoutsSinceAnchor() async -> [HKWorkout] {
        let type = HKObjectType.workoutType()
        do {
            let (samples, newAnchor): ([HKWorkout], HKQueryAnchor?) = try await anchored(sampleType: type, anchor: workoutAnchor)
            workoutAnchor = newAnchor
            return samples
        } catch {
            logger.error("Anchored workout query failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func bodyMassSamples(days: Int = 400) async -> [(uuid: UUID, date: Date, kg: Double)] {
        let type = HKQuantityType(.bodyMass)
        let start = Date.now.adding(days: -days)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date.now)
        do {
            let samples: [HKQuantitySample] = try await querySamples(of: type, predicate: predicate)
            return samples.map { ($0.uuid, $0.startDate, $0.quantity.doubleValue(for: .gramUnit(with: .kilo))) }
        } catch {
            logger.error("Body mass query failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func statisticsForWorkout(_ workout: HKWorkout) async -> (avgHR: Double?, maxHR: Double?, energy: Double?, distance: Double?) {
        let hrType = HKQuantityType(.heartRate)
        let energyType = HKQuantityType(.activeEnergyBurned)
        let distanceType = HKQuantityType(.distanceWalkingRunning)
        let hrUnit = HKUnit.count().unitDivided(by: .minute())
        async let avgStat = statistics(type: hrType, options: .discreteAverage, start: workout.startDate, end: workout.endDate)
        async let maxStat = statistics(type: hrType, options: .discreteMax, start: workout.startDate, end: workout.endDate)
        async let energyStat = statistics(type: energyType, options: .cumulativeSum, start: workout.startDate, end: workout.endDate)
        async let distanceStat = statistics(type: distanceType, options: .cumulativeSum, start: workout.startDate, end: workout.endDate)
        return (
            await avgStat?.averageQuantity()?.doubleValue(for: hrUnit),
            await maxStat?.maximumQuantity()?.doubleValue(for: hrUnit),
            await energyStat?.sumQuantity()?.doubleValue(for: .kilocalorie()),
            await distanceStat?.sumQuantity()?.doubleValue(for: .meter())
        )
    }

    // MARK: - Writes

    func saveBodyMass(kilograms: Double, date: Date = .now) async throws {
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kilograms)
        let sample = HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: quantity, start: date, end: date)
        try await store.save(sample)
        Haptics.success()
    }

    func saveDietary(entry: FoodEntry) async throws {
        let start = entry.loggedAt
        let end = start.addingTimeInterval(60)
        var samples: [HKQuantitySample] = [
            quantitySample(.dietaryEnergyConsumed, value: entry.calories, unit: .kilocalorie(), start: start, end: end),
            quantitySample(.dietaryProtein, value: entry.proteinGrams, unit: .gram(), start: start, end: end),
            quantitySample(.dietaryCarbohydrates, value: entry.carbsGrams, unit: .gram(), start: start, end: end),
            quantitySample(.dietaryFatTotal, value: entry.fatGrams, unit: .gram(), start: start, end: end)
        ]
        if entry.fiberGrams > 0 {
            samples.append(quantitySample(.dietaryFiber, value: entry.fiberGrams, unit: .gram(), start: start, end: end))
        }
        try await store.save(samples)
    }

    func saveWorkout(
        activityType: HKWorkoutActivityType,
        start: Date,
        end: Date,
        energyKilocalories: Double?,
        distanceMeters: Double?
    ) async throws -> UUID {
        // HKWorkoutBuilder is the supported write path on iOS 17+ (the
        // HKWorkout convenience initializer is deprecated).
        let workout = try await buildWorkout(
            activityType: activityType,
            start: start,
            end: end,
            energyKilocalories: energyKilocalories,
            distanceMeters: distanceMeters
        )
        Haptics.success()
        return workout.uuid
    }

    private func buildWorkout(
        activityType: HKWorkoutActivityType,
        start: Date,
        end: Date,
        energyKilocalories: Double?,
        distanceMeters: Double?
    ) async throws -> HKWorkout {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: start)
        if let energyKilocalories {
            let sample = quantitySample(.activeEnergyBurned, value: energyKilocalories, unit: .kilocalorie(), start: start, end: end)
            try await addSamples([sample], to: builder)
        }
        if let distanceMeters, distanceMeters > 0 {
            let sample = quantitySample(.distanceWalkingRunning, value: distanceMeters, unit: .meter(), start: start, end: end)
            try await addSamples([sample], to: builder)
        }
        try await builder.endCollection(at: end)
        let workout = try await builder.finishWorkout()
        guard let workout else {
            throw HealthKitManagerError.workoutBuildFailed
        }
        return workout
    }

    // MARK: - Query helpers

    private func averageQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> Double? {
        await statistics(type: HKQuantityType(identifier), options: .discreteAverage, start: start, end: end)?
            .averageQuantity()?
            .doubleValue(for: unit)
    }

    private func sumQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> Double? {
        await statistics(type: HKQuantityType(identifier), options: .cumulativeSum, start: start, end: end)?
            .sumQuantity()?
            .doubleValue(for: unit)
    }

    private func mostRecentQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> Double? {
        let type = HKQuantityType(identifier)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        do {
            let found: [HKQuantitySample] = try await querySamples(of: type, predicate: predicate, limit: 1, sortDescriptors: [sort])
            return found.first?.quantity.doubleValue(for: unit)
        } catch {
            return nil
        }
    }

    private func dailyAverages(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> [(date: Date, value: Double)] {
        let type = HKQuantityType(identifier)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage,
                anchorDate: CalendarDay.start(of: start),
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, _ in
                var points: [(Date, Double)] = []
                collection?.enumerateStatistics(from: start, to: end) { stats, _ in
                    if let value = stats.averageQuantity()?.doubleValue(for: unit) {
                        points.append((stats.startDate, value))
                    }
                }
                continuation.resume(returning: points)
            }
            self.store.execute(query)
        }
    }

    private func statistics(
        type: HKQuantityType,
        options: HKStatisticsOptions,
        start: Date,
        end: Date
    ) async -> HKStatistics? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: options) { _, stats, _ in
                continuation.resume(returning: stats)
            }
            self.store.execute(query)
        }
    }

    /// `HKWorkoutBuilder.add(_:completion:)` has no async overload, so wrap the callback.
    private func addSamples(_ samples: [HKSample], to builder: HKWorkoutBuilder) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.add(samples) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitManagerError.workoutBuildFailed)
                }
            }
        }
    }

    private func querySamples<T: HKSample>(
        of sampleType: HKSampleType,
        predicate: NSPredicate?,
        limit: Int = HKObjectQueryNoLimit,
        sortDescriptors: [NSSortDescriptor]? = nil
    ) async throws -> [T] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: predicate,
                limit: limit,
                sortDescriptors: sortDescriptors
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (results as? [T]) ?? [])
            }
            self.store.execute(query)
        }
    }

    private func anchored<T: HKSample>(
        sampleType: HKSampleType,
        anchor: HKQueryAnchor?
    ) async throws -> ([T], HKQueryAnchor?) {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: sampleType,
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, added, _, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: ((added as? [T]) ?? [], newAnchor))
            }
            self.store.execute(query)
        }
    }

    private func quantitySample(
        _ identifier: HKQuantityTypeIdentifier,
        value: Double,
        unit: HKUnit,
        start: Date,
        end: Date
    ) -> HKQuantitySample {
        HKQuantitySample(
            type: HKQuantityType(identifier),
            quantity: HKQuantity(unit: unit, doubleValue: value),
            start: start,
            end: end
        )
    }

    // MARK: - Sleep grouping

    /// Collapse HealthKit sleep category samples into per-morning nights.
    /// Consecutive samples separated by more than 90 minutes start a new night.
    static func groupSleepSamples(_ samples: [HKCategorySample], endingOn morning: Date) -> [SleepNight] {
        let mapped: [(interval: SleepStageInterval, inBed: Bool)] = samples.compactMap { sample in
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }
            let stage: SleepStage
            switch value {
            case .inBed: stage = .inBed
            case .awake: stage = .awake
            case .asleepUnspecified: stage = .asleepUnspecified
            case .asleepCore: stage = .core
            case .asleepDeep: stage = .deep
            case .asleepREM: stage = .rem
            @unknown default: stage = .asleepUnspecified
            }
            let interval = SleepStageInterval(start: sample.startDate, end: sample.endDate, stage: stage)
            return (interval, value == .inBed)
        }
        .sorted { $0.interval.start < $1.interval.start }

        guard !mapped.isEmpty else { return [] }

        var clusters: [[SleepStageInterval]] = []
        var current: [SleepStageInterval] = []
        var lastEnd: Date?

        for item in mapped {
            if let lastEnd, item.interval.start.timeIntervalSince(lastEnd) > 90 * 60 {
                if !current.isEmpty { clusters.append(current) }
                current = [item.interval]
            } else {
                current.append(item.interval)
            }
            lastEnd = max(lastEnd ?? item.interval.end, item.interval.end)
        }
        if !current.isEmpty { clusters.append(current) }

        let calendar = Calendar.current
        var nights: [SleepNight] = []
        for cluster in clusters {
            let asleepStages: Set<SleepStage> = [.core, .deep, .rem, .asleepUnspecified]
            let asleep = cluster.filter { asleepStages.contains($0.stage) }
            let totalAsleep = asleep.reduce(0) { $0 + $1.duration }
            guard totalAsleep >= 30 * 60 else { continue }

            let start = cluster.map(\.start).min() ?? Date()
            let end = cluster.map(\.end).max() ?? Date()
            let wakeMorning = calendar.startOfDay(for: end)
            let hasStaging = cluster.contains { $0.stage == .deep || $0.stage == .rem || $0.stage == .core }
            nights.append(
                SleepNight(
                    morning: wakeMorning,
                    bedtime: start,
                    wakeTime: end,
                    totalAsleep: totalAsleep,
                    timeInBed: end.timeIntervalSince(start),
                    stages: cluster.filter { $0.stage != .inBed },
                    hasStaging: hasStaging
                )
            )
        }

        // Keep the longest night per morning.
        var byMorning: [Date: SleepNight] = [:]
        for night in nights {
            if let existing = byMorning[night.morning] {
                if night.totalAsleep > existing.totalAsleep {
                    byMorning[night.morning] = night
                }
            } else {
                byMorning[night.morning] = night
            }
        }

        let cutoff = CalendarDay.start(of: morning)
        return byMorning.values
            .filter { $0.morning <= cutoff }
            .sorted { $0.morning < $1.morning }
    }
}

enum HealthKitManagerError: LocalizedError {
    case workoutBuildFailed

    var errorDescription: String? {
        switch self {
        case .workoutBuildFailed:
            String(localized: "HealthKit did not return a workout after finishWorkout().")
        }
    }
}
