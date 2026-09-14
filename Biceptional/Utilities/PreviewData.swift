import Foundation
import SwiftData

@MainActor
enum PreviewData {
    static var container: ModelContainer {
        let schema = Schema([
            DailySnapshot.self,
            WorkoutRecord.self,
            StrengthSetEntry.self,
            WeightSample.self,
            FoodEntry.self,
            CustomFood.self,
            UserPreferences.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        seed(container.mainContext)
        return container
    }

    static func seed(_ context: ModelContext) {
        let prefs = UserPreferences()
        context.insert(prefs)

        let dal = CustomFood(
            name: "Dal tadka",
            caloriesPerServing: 280,
            proteinPerServing: 14,
            carbsPerServing: 32,
            fatPerServing: 10,
            fiberPerServing: 8,
            servingSizeGrams: 250,
            servingLabel: "bowl"
        )
        context.insert(dal)

        for offset in 0..<14 {
            let day = Date.now.adding(days: -offset).startOfDay
            let snapshot = DailySnapshot(day: day)
            snapshot.recoveryScore = Double.random(in: 42...88)
            snapshot.sleepScore = Double.random(in: 55...92)
            snapshot.sleepHours = Double.random(in: 6.4...8.6)
            snapshot.strainScore = Double.random(in: 4...16)
            snapshot.strainLoad = snapshot.strainScore! * 12
            snapshot.steps = Int.random(in: 4000...14000)
            snapshot.activeCalories = Double.random(in: 280...720)
            snapshot.hrvSDNN = Double.random(in: 28...62)
            snapshot.restingHeartRate = Double.random(in: 48...62)
            snapshot.recoveryExplanation = "Recovery is around your typical range."
            context.insert(snapshot)

            context.insert(WeightSample(date: day.addingTimeInterval(7 * 3600), kilograms: 74.2 - Double(offset) * 0.04, source: "manual"))
        }

        let workout = WorkoutRecord(
            source: "manual",
            name: "Push",
            activityTypeRaw: 50,
            startDate: Date.now.addingTimeInterval(-3600 * 30),
            endDate: Date.now.addingTimeInterval(-3600 * 29),
            durationSeconds: 3600,
            activeEnergyKilocalories: 280,
            notes: "Supersetted bench with rows."
        )
        let set = StrengthSetEntry(exerciseName: "Bench press", setIndex: 1, reps: 8, weightKilograms: 70)
        set.workout = workout
        workout.sets.append(set)
        context.insert(workout)

        context.insert(
            FoodEntry(
                name: "Dal tadka",
                calories: 280,
                proteinGrams: 14,
                carbsGrams: 32,
                fatGrams: 10,
                fiberGrams: 8,
                servings: 1,
                customFoodID: dal.uuid
            )
        )
        try? context.save()
    }
}
