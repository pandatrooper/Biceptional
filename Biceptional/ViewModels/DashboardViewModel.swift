import Foundation
import HealthKit
import Observation
import SwiftData

@Observable
@MainActor
final class DashboardViewModel {
    var recovery: RecoveryResult?
    var sleep: SleepResult?
    var strain: StrainResult?
    var steps: Int = 0
    var activeCalories: Double = 0
    var weightAverageKg: Double?
    var weightStatus: WeightTrendStatus = .unknown
    var caloriesLogged: Double = 0
    var proteinLogged: Double = 0
    var calorieTarget: Double = 2400
    var proteinTarget: Double = 160
    var healthDietary: DietaryDay?
    var isRefreshing = false
    var lastExplanation: String = ""

    func load(context: ModelContext, healthKit: HealthKitManager) async {
        isRefreshing = true
        defer { isRefreshing = false }
        let prefs = ScoreRefreshService.preferences(in: context)
        calorieTarget = prefs.calorieTarget
        proteinTarget = prefs.proteinTargetGrams

        let snapshot = ScoreRefreshService.snapshot(for: .now, in: context)
        lastExplanation = snapshot.recoveryExplanation
        steps = snapshot.steps
        activeCalories = snapshot.activeCalories

        let nights = await healthKit.sleepNights(endingOn: .now, days: 14)
        let morning = CalendarDay.start(of: .now)
        let tonight = nights.last(where: { CalendarDay.start(of: $0.morning) == morning }) ?? nights.last
        sleep = ScoringEngine.sleep(
            night: tonight,
            recentNights: nights,
            targetMinHours: prefs.sleepTargetMinHours,
            targetMaxHours: prefs.sleepTargetMaxHours
        )

        let physiology = await healthKit.overnightPhysiology(morning: morning)
        async let hrvBase = healthKit.baseline(identifier: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), endingOn: morning)
        async let rhrBase = healthKit.baseline(identifier: .restingHeartRate, unit: .count().unitDivided(by: .minute()), endingOn: morning)
        async let rrBase = healthKit.baseline(identifier: .respiratoryRate, unit: .count().unitDivided(by: .minute()), endingOn: morning)
        recovery = ScoringEngine.recovery(
            physiology: physiology,
            hrvBaseline: await hrvBase,
            rhrBaseline: await rhrBase,
            rrBaseline: await rrBase,
            sleepScore: sleep?.score
        )

        let activity = await healthKit.activityTotals(on: morning)
        steps = activity.steps
        activeCalories = activity.activeEnergyKilocalories
        let zones = ScoringEngine.zoneMinutes(
            heartRatesBPM: await healthKit.heartRateSeries(on: morning),
            maxHeartRate: prefs.estimatedMaxHeartRate
        )
        strain = ScoringEngine.strain(
            zoneMinutes: zones,
            activeEnergyKilocalories: activity.activeEnergyKilocalories,
            personalMaxLoad: ScoreRefreshService.personalMaxLoad(in: context, excluding: morning)
        )

        let weights = ((try? context.fetch(FetchDescriptor<WeightSample>())) ?? [])
            .sorted { $0.date < $1.date }
            .map { (date: CalendarDay.start(of: $0.date), kg: $0.kilograms) }
        let rolling = ScoringEngine.rollingAverage(values: Self.dailyUnique(weights))
        weightAverageKg = rolling.last?.kg
        let slope = ScoringEngine.weeklySlopeKg(rolling: rolling)
        weightStatus = ScoringEngine.weightStatus(slopeKgPerWeek: slope, targetKgPerWeek: prefs.weightChangeTargetKgPerWeek)

        let foods = foodsToday(context: context)
        caloriesLogged = foods.reduce(0) { $0 + $1.calories }
        proteinLogged = foods.reduce(0) { $0 + $1.proteinGrams }
        healthDietary = await healthKit.dietaryDay(on: morning)
    }

    private func foodsToday(context: ModelContext) -> [FoodEntry] {
        let start = CalendarDay.start(of: .now)
        let end = CalendarDay.end(of: .now)
        let all = (try? context.fetch(FetchDescriptor<FoodEntry>())) ?? []
        return all.filter { $0.loggedAt >= start && $0.loggedAt < end && $0.source != "healthKitIgnored" }
    }

    private static func dailyUnique(_ values: [(date: Date, kg: Double)]) -> [(date: Date, kg: Double)] {
        var last: [Date: Double] = [:]
        for item in values { last[item.date] = item.kg }
        return last.keys.sorted().map { ($0, last[$0]!) }
    }
}

@Observable
@MainActor
final class WorkoutViewModel {
    var filter: WorkoutFilter = .all
    var search = ""

    enum WorkoutFilter: String, CaseIterable, Identifiable {
        case all, strength, cardio, imported
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: String(localized: "All")
            case .strength: String(localized: "Strength")
            case .cardio: String(localized: "Cardio")
            case .imported: String(localized: "Imported")
            }
        }
    }

    func matches(_ workout: WorkoutRecord) -> Bool {
        switch filter {
        case .all: break
        case .strength:
            if workout.sets.isEmpty { return false }
        case .cardio:
            if !workout.sets.isEmpty { return false }
        case .imported:
            if workout.source != "healthKit" { return false }
        }
        if search.isEmpty { return true }
        return workout.name.localizedCaseInsensitiveContains(search)
    }
}

@Observable
@MainActor
final class WeightViewModel {
    var range: ChartRange = .threeMonths
    var draftKg: Double = 70
    var didLog = false

    enum ChartRange: String, CaseIterable, Identifiable {
        case twoWeeks, threeMonths, oneYear, all
        var id: String { rawValue }
        var title: String {
            switch self {
            case .twoWeeks: String(localized: "2W")
            case .threeMonths: String(localized: "3M")
            case .oneYear: String(localized: "1Y")
            case .all: String(localized: "All")
            }
        }
        var days: Int? {
            switch self {
            case .twoWeeks: 14
            case .threeMonths: 90
            case .oneYear: 365
            case .all: nil
            }
        }
    }
}

@Observable
@MainActor
final class NutritionViewModel {
    var useHealthKitDay = false
    var logByGrams = false
    var draftName = ""
    var draftCalories = 0.0
    var draftProtein = 0.0
    var draftCarbs = 0.0
    var draftFat = 0.0
    var draftFiber = 0.0
    var draftGrams = 100.0
    var draftServings = 1.0
    var didLog = false
}

@Observable
@MainActor
final class TrendsViewModel {
    var sleepVsRecovery: Double?
    var strainVsRecovery: Double?
    var points: [TrendPoint] = []

    struct TrendPoint: Identifiable, Hashable {
        var id: Date { day }
        var day: Date
        var recovery: Double?
        var sleep: Double?
        var strain: Double?
        var sleepHours: Double?
        var calories: Double?
        var weightKg: Double?
    }

    func load(context: ModelContext) {
        let snapshots = ((try? context.fetch(FetchDescriptor<DailySnapshot>())) ?? [])
            .sorted { $0.day < $1.day }
        let weights = ((try? context.fetch(FetchDescriptor<WeightSample>())) ?? [])
        let foods = ((try? context.fetch(FetchDescriptor<FoodEntry>())) ?? [])

        points = snapshots.suffix(90).map { row in
            let dayStart = row.day
            let dayEnd = CalendarDay.end(of: row.day)
            let dayFoods = foods.filter { $0.loggedAt >= dayStart && $0.loggedAt < dayEnd }
            let dayWeight = weights.filter { CalendarDay.start(of: $0.date) == dayStart }.last?.kilograms
            return TrendPoint(
                day: row.day,
                recovery: row.recoveryScore,
                sleep: row.sleepScore,
                strain: row.strainScore,
                sleepHours: row.sleepHours,
                calories: dayFoods.isEmpty ? nil : dayFoods.reduce(0) { $0 + $1.calories },
                weightKg: dayWeight
            )
        }

        var sleepHours: [Double] = []
        var nextRecovery: [Double] = []
        var strain: [Double] = []
        var recoveryAfterStrain: [Double] = []
        let ordered = snapshots.sorted { $0.day < $1.day }
        for index in 0..<(ordered.count - 1) {
            if let hours = ordered[index].sleepHours, let rec = ordered[index + 1].recoveryScore {
                sleepHours.append(hours)
                nextRecovery.append(rec)
            }
            if let s = ordered[index].strainScore, let rec = ordered[index + 1].recoveryScore {
                strain.append(s)
                recoveryAfterStrain.append(rec)
            }
        }
        sleepVsRecovery = ScoringEngine.pearson(sleepHours, nextRecovery)
        strainVsRecovery = ScoringEngine.pearson(strain, recoveryAfterStrain)
    }
}
