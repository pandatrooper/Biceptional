import Foundation
import SwiftData

/// Persisted daily computed scores plus the raw inputs used to produce them.
/// One row per calendar morning — recomputed whenever HealthKit background
/// delivery reports new overnight samples.
@Model
final class DailySnapshot {
    var day: Date
    var recoveryScore: Double?
    var recoveryExplanation: String
    var recoveryJSON: Data?
    var sleepScore: Double?
    var sleepExplanation: String
    var sleepHours: Double?
    var strainScore: Double?
    var strainLoad: Double
    var steps: Int
    var activeCalories: Double
    var hrvSDNN: Double?
    var restingHeartRate: Double?
    var respiratoryRate: Double?
    var updatedAt: Date

    init(day: Date) {
        self.day = CalendarDay.start(of: day)
        self.recoveryExplanation = ""
        self.sleepExplanation = ""
        self.strainLoad = 0
        self.steps = 0
        self.activeCalories = 0
        self.updatedAt = .now
    }
}

@Model
final class WorkoutRecord {
    var uuid: UUID
    var healthKitUUID: UUID?
    var source: String
    var name: String
    var activityTypeRaw: UInt
    var startDate: Date
    var endDate: Date
    var durationSeconds: Double
    var distanceMeters: Double?
    var activeEnergyKilocalories: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var strain: Double?
    var notes: String
    var isLive: Bool

    @Relationship(deleteRule: .cascade, inverse: \StrengthSetEntry.workout)
    var sets: [StrengthSetEntry]

    init(
        uuid: UUID = UUID(),
        healthKitUUID: UUID? = nil,
        source: String,
        name: String,
        activityTypeRaw: UInt,
        startDate: Date,
        endDate: Date,
        durationSeconds: Double,
        distanceMeters: Double? = nil,
        activeEnergyKilocalories: Double? = nil,
        averageHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        strain: Double? = nil,
        notes: String = "",
        isLive: Bool = false,
        sets: [StrengthSetEntry] = []
    ) {
        self.uuid = uuid
        self.healthKitUUID = healthKitUUID
        self.source = source
        self.name = name
        self.activityTypeRaw = activityTypeRaw
        self.startDate = startDate
        self.endDate = endDate
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.strain = strain
        self.notes = notes
        self.isLive = isLive
        self.sets = sets
    }

    var duration: TimeInterval { durationSeconds }
}

@Model
final class StrengthSetEntry {
    var uuid: UUID
    var exerciseName: String
    var setIndex: Int
    var reps: Int
    var weightKilograms: Double
    var restSeconds: Int
    var notes: String
    /// Sets sharing this ID were performed as a superset.
    var supersetGroupID: UUID?
    var workout: WorkoutRecord?

    init(
        uuid: UUID = UUID(),
        exerciseName: String,
        setIndex: Int,
        reps: Int,
        weightKilograms: Double,
        restSeconds: Int = 90,
        notes: String = "",
        supersetGroupID: UUID? = nil
    ) {
        self.uuid = uuid
        self.exerciseName = exerciseName
        self.setIndex = setIndex
        self.reps = reps
        self.weightKilograms = weightKilograms
        self.restSeconds = restSeconds
        self.notes = notes
        self.supersetGroupID = supersetGroupID
    }
}

@Model
final class WeightSample {
    var uuid: UUID
    var healthKitUUID: UUID?
    var date: Date
    var kilograms: Double
    var source: String

    init(uuid: UUID = UUID(), healthKitUUID: UUID? = nil, date: Date, kilograms: Double, source: String) {
        self.uuid = uuid
        self.healthKitUUID = healthKitUUID
        self.date = date
        self.kilograms = kilograms
        self.source = source
    }
}

@Model
final class FoodEntry {
    var uuid: UUID
    var loggedAt: Date
    var name: String
    var calories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var fiberGrams: Double
    var grams: Double?
    var servings: Double
    var source: String
    var customFoodID: UUID?

    init(
        uuid: UUID = UUID(),
        loggedAt: Date = .now,
        name: String,
        calories: Double,
        proteinGrams: Double,
        carbsGrams: Double,
        fatGrams: Double,
        fiberGrams: Double = 0,
        grams: Double? = nil,
        servings: Double = 1,
        source: String = "inApp",
        customFoodID: UUID? = nil
    ) {
        self.uuid = uuid
        self.loggedAt = loggedAt
        self.name = name
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.grams = grams
        self.servings = servings
        self.source = source
        self.customFoodID = customFoodID
    }
}

@Model
final class CustomFood {
    var uuid: UUID
    var name: String
    var caloriesPerServing: Double
    var proteinPerServing: Double
    var carbsPerServing: Double
    var fatPerServing: Double
    var fiberPerServing: Double
    /// Grams that constitute one serving. Used when logging by weight.
    var servingSizeGrams: Double
    var servingLabel: String
    var useCount: Int
    var lastUsedAt: Date

    init(
        uuid: UUID = UUID(),
        name: String,
        caloriesPerServing: Double,
        proteinPerServing: Double,
        carbsPerServing: Double,
        fatPerServing: Double,
        fiberPerServing: Double = 0,
        servingSizeGrams: Double = 100,
        servingLabel: String = "serving"
    ) {
        self.uuid = uuid
        self.name = name
        self.caloriesPerServing = caloriesPerServing
        self.proteinPerServing = proteinPerServing
        self.carbsPerServing = carbsPerServing
        self.fatPerServing = fatPerServing
        self.fiberPerServing = fiberPerServing
        self.servingSizeGrams = servingSizeGrams
        self.servingLabel = servingLabel
        self.useCount = 0
        self.lastUsedAt = .now
    }

    func macros(servings: Double) -> (kcal: Double, protein: Double, carbs: Double, fat: Double, fiber: Double) {
        (
            caloriesPerServing * servings,
            proteinPerServing * servings,
            carbsPerServing * servings,
            fatPerServing * servings,
            fiberPerServing * servings
        )
    }

    func macros(grams: Double) -> (kcal: Double, protein: Double, carbs: Double, fat: Double, fiber: Double, servings: Double) {
        let servings = servingSizeGrams > 0 ? grams / servingSizeGrams : 0
        let m = macros(servings: servings)
        return (m.kcal, m.protein, m.carbs, m.fat, m.fiber, servings)
    }
}

/// Single-row settings store. Editable phase targets live here rather than
/// being hardcoded in scoring or views.
@Model
final class UserPreferences {
    var sleepTargetMinHours: Double
    var sleepTargetMaxHours: Double
    var calorieTarget: Double
    var proteinTargetGrams: Double
    var carbTargetGrams: Double
    var fatTargetGrams: Double
    var fiberTargetGrams: Double
    /// kg per week. Negative = intended loss.
    var weightChangeTargetKgPerWeek: Double
    var ageYears: Int
    var restingHeartRateFloor: Double
    var notificationsEnabled: Bool
    var morningRecoveryHour: Int
    var weightReminderHour: Int
    var foodReminderHour: Int

    init() {
        self.sleepTargetMinHours = 7.5
        self.sleepTargetMaxHours = 8.5
        self.calorieTarget = 2400
        self.proteinTargetGrams = 160
        self.carbTargetGrams = 250
        self.fatTargetGrams = 70
        self.fiberTargetGrams = 35
        self.weightChangeTargetKgPerWeek = -0.4
        self.ageYears = 30
        self.restingHeartRateFloor = 40
        self.notificationsEnabled = true
        self.morningRecoveryHour = 7
        self.weightReminderHour = 7
        self.foodReminderHour = 21
    }

    var estimatedMaxHeartRate: Double {
        // Tanaka et al. 2001: 208 − 0.7 × age. Preferable to 220 − age.
        208 - 0.7 * Double(ageYears)
    }
}
