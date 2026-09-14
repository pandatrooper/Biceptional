import SwiftUI
import SwiftData

/// Owns HealthKit + notifications on the main actor so `HKHealthStore` is
/// never created from `App.init` (which is not main-threaded).
struct RootView: View {
    @State private var healthKit = HealthKitManager()
    @State private var notifications = NotificationService()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ContentView()
            .environment(healthKit)
            .task {
                await healthKit.restoreBackgroundDeliveryIfPossible()
                _ = ScoreRefreshService.preferences(in: modelContext)
                healthKit.onDataDidChange = {
                    Task { @MainActor in
                        await ScoreRefreshService(healthKit: healthKit).refresh(context: modelContext)
                    }
                }
                if healthKit.authorizationState == .sharingAuthorized {
                    await ScoreRefreshService(healthKit: healthKit).refresh(context: modelContext)
                }
                await notifications.reschedule(preferences: ScoreRefreshService.preferences(in: modelContext))
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, healthKit.authorizationState == .sharingAuthorized {
                    Task {
                        await ScoreRefreshService(healthKit: healthKit).refresh(context: modelContext)
                    }
                }
            }
    }
}

struct ContentView: View {
    @Environment(HealthKitManager.self) private var healthKit

    var body: some View {
        Group {
            if showsHealthGate {
                HealthAuthView()
            } else {
                mainTabs
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    /// First-launch Health prompt is the root view, not a sheet on top of
    /// TabView. An undismissable sheet with a no-op Binding commonly paints
    /// a blank window on device.
    private var showsHealthGate: Bool {
        switch healthKit.authorizationState {
        case .notRequested, .requesting: true
        default: false
        }
    }

    private var mainTabs: some View {
        TabView {
            DashboardView()
                .tabItem { Label(String(localized: "Today"), systemImage: "sun.max.fill") }
            WorkoutsView()
                .tabItem { Label(String(localized: "Workouts"), systemImage: "figure.run") }
            NutritionView()
                .tabItem { Label(String(localized: "Nutrition"), systemImage: "fork.knife") }
            TrendsView()
                .tabItem { Label(String(localized: "Trends"), systemImage: "chart.xyaxis.line") }
            SettingsView()
                .tabItem { Label(String(localized: "Settings"), systemImage: "gear") }
        }
    }
}

struct HealthAuthView: View {
    @Environment(HealthKitManager.self) private var healthKit

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "heart.text.clipboard.fill")
                        .font(.system(size: 48))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.pink)
                        .accessibilityHidden(true)

                    Text(String(localized: "Biceptional reads Apple Health"))
                        .font(.largeTitle.bold())

                    Text(String(localized: "Recovery, Sleep, and Strain are computed on this device from HRV, resting heart rate, sleep, workouts, and nutrition. Nothing is sent to a server."))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        label(String(localized: "Read"), String(localized: "HRV, heart rate, sleep, energy, workouts, weight, VO₂ max, dietary macros"))
                        label(String(localized: "Write"), String(localized: "Workouts, body mass, and meals you log"))
                    }

                    Button {
                        Task { await healthKit.requestAuthorization() }
                    } label: {
                        Text(healthKit.authorizationState == .requesting
                             ? String(localized: "Requesting…")
                             : String(localized: "Continue"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(healthKit.authorizationState == .requesting)
                    .padding(.top, 12)

                    Button(String(localized: "Browse without Health")) {
                        healthKit.skipAuthorization()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 24)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func label(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
