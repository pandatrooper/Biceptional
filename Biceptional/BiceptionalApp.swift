import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct BiceptionalApp: App {
    @State private var healthKit = HealthKitManager()
    @State private var notifications = NotificationService()
    @Environment(\.scenePhase) private var scenePhase

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
            ContentView()
                .environment(healthKit)
                .task {
                    await healthKit.restoreBackgroundDeliveryIfPossible()
                    let context = container.mainContext
                    _ = ScoreRefreshService.preferences(in: context)
                    healthKit.onDataDidChange = {
                        Task { @MainActor in
                            await ScoreRefreshService(healthKit: healthKit).refresh(context: container.mainContext)
                        }
                    }
                    if UserDefaults.standard.bool(forKey: "didRequestHealthAuth"), healthKit.isHealthDataAvailable {
                        await ScoreRefreshService(healthKit: healthKit).refresh(context: context)
                    }
                    await notifications.reschedule(preferences: ScoreRefreshService.preferences(in: context))
                    await scheduleBackgroundRefresh()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task {
                            await ScoreRefreshService(healthKit: healthKit).refresh(context: container.mainContext)
                        }
                    }
                }
        }
        .modelContainer(container)
    }

    private func scheduleBackgroundRefresh() async {
        let request = BGAppRefreshTaskRequest(identifier: "com.pandatrooper.Biceptional.refreshScores")
        request.earliestBeginDate = Date.now.addingTimeInterval(60 * 60)
        try? await BGTaskScheduler.shared.submitTaskRequest(request)
    }
}
