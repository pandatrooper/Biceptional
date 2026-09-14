import Foundation
import HealthKit
import SwiftData
import WidgetKit

/// Recomputes Recovery / Sleep / Strain for a calendar day, persists a
/// `DailySnapshot`, mirrors a compact payload into the App Group for widgets,
/// and imports any HealthKit workouts that are not already in SwiftData.
@MainActor
final class ScoreRefreshService {
    private let healthKit: HealthKitManager
    private var isRefreshing = false

    init(healthKit: HealthKitManager) {
        self.healthKit = healthKit
    }

    func refresh(day: Date = .now, context: ModelContext) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let prefs = Self.preferences(in: context)
        let morning = CalendarDay.start(of: day)

        async let physiology = healthKit.overnightPhysiology(morning: morning)
        async let hrvBase = healthKit.baseline(identifier: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), endingOn: morning)
        async let rhrBase = healthKit.baseline(identifier: .restingHeartRate, unit: .count().unitDivided(by: .minute()), endingOn: morning)
        async let rrBase = healthKit.baseline(identifier: .respiratoryRate, unit: .count().unitDivided(by: .minute()), endingOn: morning)
        async let nights = healthKit.sleepNights(endingOn: morning, days: 14)
        async let activity = healthKit.activityTotals(on: morning)
        async let heartRates = healthKit.heartRateSeries(on: morning)

        let sleepNights = await nights
        let tonight = sleepNights.last(where: { CalendarDay.start(of: $0.morning) == morning }) ?? sleepNights.last
        let sleep = ScoringEngine.sleep(
            night: tonight,
            recentNights: sleepNights,
            targetMinHours: prefs.sleepTargetMinHours,
            targetMaxHours: prefs.sleepTargetMaxHours
        )
        let recovery = ScoringEngine.recovery(
            physiology: await physiology,
            hrvBaseline: await hrvBase,
            rhrBaseline: await rhrBase,
            rrBaseline: await rrBase,
            sleepScore: sleep.score
        )

        let totals = await activity
        let zones = ScoringEngine.zoneMinutes(
            heartRatesBPM: await heartRates,
            maxHeartRate: prefs.estimatedMaxHeartRate
        )
        let personalMax = Self.personalMaxLoad(in: context, excluding: morning)
        let strain = ScoringEngine.strain(
            zoneMinutes: zones,
            activeEnergyKilocalories: totals.activeEnergyKilocalories,
            personalMaxLoad: personalMax
        )

        let snapshot = Self.snapshot(for: morning, in: context)
        snapshot.recoveryScore = recovery.score
        snapshot.recoveryExplanation = recovery.explanation
        snapshot.recoveryJSON = try? JSONEncoder().encode(recovery.components.map(CodableComponent.init))
        snapshot.sleepScore = sleep.score
        snapshot.sleepExplanation = sleep.explanation
        snapshot.sleepHours = sleep.night?.asleepHours
        snapshot.strainScore = strain.score
        snapshot.strainLoad = strain.load
        snapshot.steps = totals.steps
        snapshot.activeCalories = totals.activeEnergyKilocalories
        snapshot.hrvSDNN = await physiology.hrvSDNN
        snapshot.restingHeartRate = await physiology.restingHeartRate
        snapshot.respiratoryRate = await physiology.respiratoryRate
        snapshot.updatedAt = .now

        TodaySnapshotPayload(
            date: morning,
            recoveryScore: recovery.score,
            recoveryExplanation: recovery.explanation,
            sleepScore: sleep.score,
            sleepHours: sleep.night?.asleepHours,
            strainScore: strain.score,
            steps: totals.steps,
            activeCalories: totals.activeEnergyKilocalories
        ).save()
        WidgetCenter.shared.reloadAllTimelines()

        await importWorkouts(context: context)
        await importWeight(context: context)

        try? context.save()
    }

    func importWorkouts(context: ModelContext) async {
        let workouts = await healthKit.recentWorkouts(limit: 120)
        let existing = (try? context.fetch(FetchDescriptor<WorkoutRecord>())) ?? []
        let knownHK = Set(existing.compactMap(\.healthKitUUID))

        for workout in workouts {
            if knownHK.contains(workout.uuid) { continue }
            let stats = await healthKit.statisticsForWorkout(workout)
            let record = WorkoutRecord(
                healthKitUUID: workout.uuid,
                source: "healthKit",
                name: workout.workoutActivityType.biceptionalName,
                activityTypeRaw: workout.workoutActivityType.rawValue,
                startDate: workout.startDate,
                endDate: workout.endDate,
                durationSeconds: workout.duration,
                distanceMeters: stats.distance ?? workout.totalDistance?.doubleValue(for: .meter()),
                activeEnergyKilocalories: stats.energy ?? workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                averageHeartRate: stats.avgHR,
                maxHeartRate: stats.maxHR
            )
            context.insert(record)
        }
    }

    private func importWeight(context: ModelContext) async {
        let samples = await healthKit.bodyMassSamples()
        let existing = (try? context.fetch(FetchDescriptor<WeightSample>())) ?? []
        let known = Set(existing.compactMap(\.healthKitUUID))
        for sample in samples {
            if known.contains(sample.uuid) { continue }
            context.insert(
                WeightSample(
                    healthKitUUID: sample.uuid,
                    date: sample.date,
                    kilograms: sample.kg,
                    source: "healthKit"
                )
            )
        }
    }

    static func preferences(in context: ModelContext) -> UserPreferences {
        if let existing = try? context.fetch(FetchDescriptor<UserPreferences>()).first {
            return existing
        }
        let prefs = UserPreferences()
        context.insert(prefs)
        return prefs
    }

    static func snapshot(for day: Date, in context: ModelContext) -> DailySnapshot {
        let start = CalendarDay.start(of: day)
        var descriptor = FetchDescriptor<DailySnapshot>(
            predicate: #Predicate { $0.day == start }
        )
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let created = DailySnapshot(day: start)
        context.insert(created)
        return created
    }

    static func personalMaxLoad(in context: ModelContext, excluding day: Date) -> Double {
        let rows = (try? context.fetch(FetchDescriptor<DailySnapshot>())) ?? []
        let start = CalendarDay.start(of: day)
        let windowStart = start.adding(days: -30)
        let loads = rows
            .filter { $0.day >= windowStart && $0.day < start }
            .map(\.strainLoad)
            .filter { $0 > 0 }
        return loads.max() ?? 80
    }
}

private struct CodableComponent: Codable {
    var name: String
    var weight: Double
    var score: Double?
    var zScore: Double?

    init(_ component: RecoveryComponent) {
        name = component.name
        weight = component.weight
        score = component.score
        zScore = component.zScore
    }
}

extension HKWorkoutActivityType {
    var biceptionalName: String {
        switch self {
        case .traditionalStrengthTraining: String(localized: "Strength")
        case .functionalStrengthTraining: String(localized: "Functional strength")
        case .running: String(localized: "Run")
        case .cycling: String(localized: "Ride")
        case .walking: String(localized: "Walk")
        case .hiking: String(localized: "Hike")
        case .yoga: String(localized: "Yoga")
        case .swimming: String(localized: "Swim")
        case .coreTraining: String(localized: "Core")
        case .flexibility: String(localized: "Mobility")
        case .highIntensityIntervalTraining: String(localized: "HIIT")
        case .mixedCardio: String(localized: "Cardio")
        case .stairClimbing: String(localized: "Stairs")
        default: String(localized: "Workout")
        }
    }
}

