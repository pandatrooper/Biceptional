import SwiftUI

struct SleepCardView: View {
    var result: SleepResult?

    var body: some View {
        NavigationLink {
            SleepDetailView(result: result)
        } label: {
            MetricCard(title: String(localized: "Sleep"), systemImage: "moon.zzz.fill") {
                HStack(alignment: .firstTextBaseline) {
                    Text(scoreText)
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .foregroundStyle(Color.recoveryBand(result?.score))
                    Spacer()
                    if let hours = result?.night?.asleepHours {
                        Text(Formatters.hours(hours))
                            .font(.title3.monospacedDigit())
                    }
                }
                if let night = result?.night {
                    SleepStageBar(night: night)
                        .frame(height: 14)
                        .clipShape(Capsule())
                        .padding(.top, 4)
                }
                Text(result?.explanation ?? String(localized: "No sleep recorded last night."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "Opens sleep detail and hypnogram"))
    }

    private var scoreText: String {
        guard let score = result?.score else { return "—" }
        return score.formatted(.number.precision(.fractionLength(0)))
    }
}

struct SleepStageBar: View {
    var night: SleepNight

    var body: some View {
        GeometryReader { proxy in
            let total = max(night.timeInBed, 1)
            HStack(spacing: 1) {
                ForEach(night.stages) { interval in
                    Capsule()
                        .fill(color(for: interval.stage))
                        .frame(width: max(1, proxy.size.width * interval.duration / total))
                        .accessibilityLabel(interval.stage.localizedName)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Sleep stages"))
    }

    private func color(for stage: SleepStage) -> Color {
        switch stage {
        case .deep: .indigo
        case .core, .asleepUnspecified: .blue
        case .rem: .purple
        case .awake: .orange
        case .inBed: .secondary.opacity(0.3)
        }
    }
}

struct StrainMeterView: View {
    var result: StrainResult?

    var body: some View {
        MetricCard(title: String(localized: "Strain"), systemImage: "bolt.heart.fill") {
            Gauge(value: result?.score ?? 0, in: 0...21) {
                Text(String(localized: "Strain"))
            } currentValueLabel: {
                Text((result?.score ?? 0).formatted(.number.precision(.fractionLength(1))))
                    .font(.system(.title2, design: .rounded).weight(.bold))
            }
            .gaugeStyle(.linearCapacity)
            .tint(Color.strainBand(result?.score))
            Text(result?.explanation ?? String(localized: "Strain updates from heart rate and active energy as the day goes on."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            (result?.score ?? 0).formatted(.number.precision(.fractionLength(1))) + String(localized: " out of 21")
        )
    }
}

struct QuickStatsRow: View {
    var steps: Int
    var activeCalories: Double
    var weightKg: Double?
    var weightStatus: WeightTrendStatus
    var caloriesLogged: Double
    var calorieTarget: Double
    var proteinLogged: Double
    var proteinTarget: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Today at a glance"))
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                stat(String(localized: "Steps"), value: steps.formatted(), symbol: "figure.walk")
                stat(String(localized: "Active"), value: Formatters.kcal(activeCalories), symbol: "flame.fill")
                stat(
                    String(localized: "Weight · 7-day"),
                    value: weightKg.map { Formatters.kilograms($0) } ?? "—",
                    symbol: "scalemass.fill",
                    footnote: weightStatus.localizedName
                )
                stat(
                    String(localized: "Food"),
                    value: "\(Int(caloriesLogged))/\(Int(calorieTarget))",
                    symbol: "fork.knife",
                    footnote: String(localized: "\(Int(proteinLogged))/\(Int(proteinTarget)) g protein")
                )
            }
        }
    }

    private func stat(_ title: String, value: String, symbol: String, footnote: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
