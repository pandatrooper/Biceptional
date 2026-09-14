import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKit
    @State private var model = DashboardViewModel()
    @State private var showLogWorkout = false
    @State private var showLogWeight = false
    @State private var showLogFood = false
    @Query(sort: \DailySnapshot.day, order: .reverse) private var snapshots: [DailySnapshot]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    recoveryBlock
                    SleepCardView(result: model.sleep)
                    StrainMeterView(result: model.strain)
                    QuickStatsRow(
                        steps: model.steps,
                        activeCalories: model.activeCalories,
                        weightKg: model.weightAverageKg,
                        weightStatus: model.weightStatus,
                        caloriesLogged: model.caloriesLogged,
                        calorieTarget: model.calorieTarget,
                        proteinLogged: model.proteinLogged,
                        proteinTarget: model.proteinTarget
                    )
                    if let health = model.healthDietary, health.energyKilocalories > model.caloriesLogged {
                        healthNutritionBanner(health)
                    }
                    NavigationLink {
                        WeightView()
                    } label: {
                        Label(String(localized: "Weight history"), systemImage: "chart.line.uptrend.xyaxis")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    quickAdd
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle(String(localized: "Today"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if model.isRefreshing {
                        ProgressView()
                            .accessibilityLabel(String(localized: "Refreshing Health data"))
                    }
                }
            }
            .refreshable {
                await refresh()
            }
            .task {
                guard healthKit.authorizationState != .notRequested else { return }
                await refresh()
            }
            .onChange(of: healthKit.authorizationState) { _, state in
                if state == .sharingAuthorized {
                    Task { await refresh() }
                }
            }
            .sheet(isPresented: $showLogWorkout) {
                LogWorkoutView()
            }
            .sheet(isPresented: $showLogWeight) {
                LogWeightView()
            }
            .sheet(isPresented: $showLogFood) {
                LogFoodView()
            }
        }
    }

    private var recoveryBlock: some View {
        NavigationLink {
            RecoveryDetailView(result: model.recovery)
        } label: {
            VStack(spacing: 16) {
                ScoreRing(
                    score: model.recovery?.score,
                    color: .recoveryBand(model.recovery?.score)
                )
                .frame(width: 180, height: 180)
                .padding(.top, 8)

                Text(model.recovery?.explanation ?? String(localized: "Waiting for overnight Health data."))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                if model.recovery?.usedLimitedData == true {
                    Text(String(localized: "Computed from limited inputs — more nights will tighten your baseline."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "Shows how Recovery was calculated"))
    }

    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Quick add"))
                .font(.headline)
            HStack(spacing: 12) {
                quickButton(String(localized: "Log Workout"), systemImage: "figure.strengthtraining.traditional") {
                    showLogWorkout = true
                }
                quickButton(String(localized: "Log Weight"), systemImage: "scalemass") {
                    showLogWeight = true
                }
                quickButton(String(localized: "Log Food"), systemImage: "fork.knife") {
                    showLogFood = true
                }
            }
        }
    }

    private func quickButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func healthNutritionBanner(_ day: DietaryDay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(String(localized: "Health already has nutrition for today"), systemImage: "heart.text.clipboard")
                .font(.subheadline.weight(.semibold))
            Text(String(localized: "\(Formatters.kcal(day.energyKilocalories)) · \(Formatters.grams(day.proteinGrams)) protein from other apps. Open Nutrition to use those totals instead of double-logging."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func refresh() async {
        let service = ScoreRefreshService(healthKit: healthKit)
        await service.refresh(context: modelContext)
        await model.load(context: modelContext, healthKit: healthKit)
    }
}

#Preview {
    DashboardView()
        .environment(HealthKitManager())
        .modelContainer(PreviewData.container)
}
