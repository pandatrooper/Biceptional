import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(HealthKitManager.self) private var healthKit

    var body: some View {
        TabView {
            Tab(String(localized: "Today"), systemImage: "sun.max.fill") {
                DashboardView()
            }
            Tab(String(localized: "Workouts"), systemImage: "figure.run") {
                WorkoutsView()
            }
            Tab(String(localized: "Nutrition"), systemImage: "fork.knife") {
                NutritionView()
            }
            Tab(String(localized: "Trends"), systemImage: "chart.xyaxis.line") {
                TrendsView()
            }
            Tab(String(localized: "Settings"), systemImage: "gear") {
                SettingsView()
            }
        }
        .sheet(isPresented: bindAuthSheet) {
            HealthAuthView()
                .interactiveDismissDisabled()
        }
    }

    private var bindAuthSheet: Binding<Bool> {
        Binding(
            get: {
                healthKit.authorizationState == .notRequested || healthKit.authorizationState == .requesting
            },
            set: { _ in }
        )
    }
}

struct HealthAuthView: View {
    @Environment(HealthKitManager.self) private var healthKit

    var body: some View {
        NavigationStack {
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

                Spacer()

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
                .disabled(healthKit.authorizationState == .requesting || healthKit.authorizationState == .unavailable)

                Button(String(localized: "Browse without Health")) {
                    healthKit.skipAuthorization()
                }
                .padding(.top, 4)

                if healthKit.authorizationState == .unavailable {
                    Text(String(localized: "Health data is not available on this device. You can still browse the UI."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
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
