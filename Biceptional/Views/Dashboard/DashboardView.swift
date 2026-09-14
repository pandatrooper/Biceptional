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
                VStack(alignment: .leading, spacing: 22) {
                    header
                    hero
                    threeUp
                    SleepCardView(
                        result: model.sleep,
                        targetMinHours: model.sleepTargetMinHours,
                        targetMaxHours: model.sleepTargetMaxHours
                    )
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
                    logRow
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color.canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(String(localized: "Today"))
                        .font(.headline)
                }
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
            .sheet(isPresented: $showLogWorkout) { LogWorkoutView() }
            .sheet(isPresented: $showLogWeight) { LogWeightView() }
            .sheet(isPresented: $showLogFood) { LogFoodView() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(Theme.display(28, weight: .bold))
            WeekStrip(snapshots: Array(snapshots.prefix(14)))
            UpdatedCaption(date: model.updatedAt)
        }
    }

    private var hero: some View {
        NavigationLink {
            RecoveryDetailView(result: model.recovery)
        } label: {
            BiceptionalCard {
                VStack(spacing: 16) {
                    HeroRing(score: model.recovery?.score)
                        .frame(width: 220, height: 220)
                        .padding(.top, 4)
                    Text(model.recovery?.explanation ?? String(localized: "Wear the Watch overnight to compute Recovery."))
                        .font(Theme.coach)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)
                    if model.recovery?.usedLimitedData == true {
                        Text(String(localized: "Wear the Watch overnight to tighten HRV."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "Shows how Recovery was calculated"))
    }

    private var threeUp: some View {
        HStack(spacing: 10) {
            NavigationLink {
                SleepDetailView(result: model.sleep)
            } label: {
                MiniMetric(
                    title: String(localized: "Sleep"),
                    value: model.sleep?.night.map { Formatters.hours($0.asleepHours) } ?? "—",
                    footnote: model.sleep?.score.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—",
                    color: .recoveryBand(model.sleep?.score)
                )
            }
            .buttonStyle(.plain)

            MiniMetric(
                title: String(localized: "Strain"),
                value: (model.strain?.score ?? 0).formatted(.number.precision(.fractionLength(1))),
                footnote: String(localized: "/ 21"),
                color: .strainBand(model.strain?.score)
            )

            MiniMetric(
                title: String(localized: "HRV"),
                value: model.hrvSDNN.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—",
                footnote: model.hrvBaseline.map { String(localized: "avg \($0.formatted(.number.precision(.fractionLength(0))))") } ?? "ms",
                color: .recoveryGreen
            )
        }
    }

    private var logRow: some View {
        HStack(spacing: 10) {
            logCapsule(String(localized: "Workout"), systemImage: "figure.strengthtraining.traditional") {
                showLogWorkout = true
            }
            logCapsule(String(localized: "Weight"), systemImage: "scalemass") {
                showLogWeight = true
            }
            logCapsule(String(localized: "Food"), systemImage: "fork.knife") {
                showLogFood = true
            }
        }
    }

    private func logCapsule(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.cardFill, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Log \(title)"))
    }

    private func healthNutritionBanner(_ day: DietaryDay) -> some View {
        BiceptionalCard {
            VStack(alignment: .leading, spacing: 6) {
                Label(String(localized: "Health already has nutrition for today"), systemImage: "heart.text.clipboard")
                    .font(.subheadline.weight(.semibold))
                Text(String(localized: "\(Formatters.kcal(day.energyKilocalories)) · \(Formatters.grams(day.proteinGrams)) protein from other apps."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func refresh() async {
        let service = ScoreRefreshService(healthKit: healthKit)
        await service.refresh(context: modelContext)
        await model.load(context: modelContext, healthKit: healthKit)
    }
}

struct MiniMetric: View {
    var title: String
    var value: String
    var footnote: String
    var color: Color

    var body: some View {
        BiceptionalCard(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: title)
                Text(value)
                    .font(Theme.display(22))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    DashboardView()
        .environment(HealthKitManager())
        .modelContainer(PreviewData.container)
}
