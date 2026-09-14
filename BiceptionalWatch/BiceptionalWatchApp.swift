import SwiftUI
import HealthKit

@main
struct BiceptionalWatchApp: App {
    @State private var health = WatchHealthService()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(health)
                .task { await health.requestAuthorization() }
        }
    }
}

struct WatchRootView: View {
    @Environment(WatchHealthService.self) private var health

    var body: some View {
        TabView {
            WatchDashboardView()
            WatchWorkoutView()
        }
        .tabViewStyle(.verticalPage)
    }
}

struct WatchDashboardView: View {
    @Environment(WatchHealthService.self) private var health

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Biceptional"))
                    .font(.headline)
                HStack {
                    metric(String(localized: "HR"), health.currentHeartRate.map { "\(Int($0))" } ?? "—")
                    metric(String(localized: "kcal"), "\(Int(health.activeCalories))")
                }
                Text(health.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle(String(localized: "Today"))
        .task { await health.refreshSnapshot() }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WatchWorkoutView: View {
    @Environment(WatchHealthService.self) private var health
    @State private var started = false

    var body: some View {
        VStack(spacing: 12) {
            if health.isWorkoutRunning {
                Text(health.elapsed.formatted())
                    .font(.title.monospacedDigit())
                Text(health.currentHeartRate.map { "\(Int($0)) bpm" } ?? String(localized: "Waiting for HR"))
                Text(String(localized: "Strain \(health.liveStrain.formatted(.number.precision(.fractionLength(1))))"))
                    .font(.footnote)
                Button(role: .destructive) {
                    Task { await health.endWorkout() }
                    started = false
                } label: {
                    Text(String(localized: "End"))
                }
                .sensoryFeedback(.impact(weight: .heavy), trigger: started)
            } else {
                Button {
                    Task { await health.startWorkout() }
                    started = true
                } label: {
                    Text(String(localized: "Start workout"))
                }
                .sensoryFeedback(.start, trigger: started)
            }
        }
        .navigationTitle(String(localized: "Workout"))
    }
}
