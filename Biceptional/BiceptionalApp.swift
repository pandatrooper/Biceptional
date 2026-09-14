import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct BiceptionalApp: App {
    private let container: ModelContainer

    init() {
        let schema = Schema([
            DailySnapshot.self,
            WorkoutRecord.self,
            StrengthSetEntry.self,
            WeightSample.self,
            FoodEntry.self,
            CustomFood.self,
            UserPreferences.self
        ])
        let configuration = ModelConfiguration(
            "Biceptional",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Persistent store failed (schema migration, disk). Fall back to
            // in-memory so the UI still launches; scores will recompute from Health.
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: schema, configurations: [fallback])
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.pandatrooper.Biceptional.refreshScores",
            using: nil
        ) { task in
            let request = BGAppRefreshTaskRequest(identifier: "com.pandatrooper.Biceptional.refreshScores")
            request.earliestBeginDate = Date.now.addingTimeInterval(60 * 60)
            BGTaskScheduler.shared.submitTaskRequest(request) { _ in }
            task.setTaskCompleted(success: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
        }
    }
}
