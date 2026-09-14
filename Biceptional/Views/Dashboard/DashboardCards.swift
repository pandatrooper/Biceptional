import SwiftUI

struct SleepCardView: View {
    var result: SleepResult?
    var targetMinHours: Double
    var targetMaxHours: Double

    var body: some View {
        NavigationLink {
            SleepDetailView(result: result)
        } label: {
            BiceptionalCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionLabel(text: String(localized: "Sleep"))
                        Spacer()
                        if let score = result?.score {
                            Text(score.formatted(.number.precision(.fractionLength(0))))
                                .font(Theme.display(22))
                                .foregroundStyle(Color.recoveryBand(score))
                                .monospacedDigit()
                        }
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(hoursText)
                            .font(Theme.display(26))
                            .monospacedDigit()
                        Text(targetText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let night = result?.night {
                        SleepStageBar(night: night, height: 18)
                        HStack {
                            Text(Formatters.shortTime.string(from: night.bedtime))
                            Spacer()
                            Text(Formatters.shortTime.string(from: night.wakeTime))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    }
                    Text(result?.explanation ?? String(localized: "No sleep recorded last night."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "Opens sleep detail and hypnogram"))
    }

    private var hoursText: String {
        guard let hours = result?.night?.asleepHours else { return "—" }
        return Formatters.hours(hours)
    }

    private var targetText: String {
        let min = targetMinHours.formatted(.number.precision(.fractionLength(1)))
        let max = targetMaxHours.formatted(.number.precision(.fractionLength(1)))
        return String(localized: "· \(min)–\(max)h")
    }
}

struct StrainMeterView: View {
    var result: StrainResult?

    private var intensity: StrainIntensity { StrainIntensity(score: result?.score) }

    var body: some View {
        BiceptionalCard {
            HStack(alignment: .center, spacing: 16) {
                StrainArc(score: result?.score)
                    .frame(width: 108, height: 108)
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: String(localized: "Strain"))
                    Text(intensity.localizedName)
                        .font(Theme.display(22))
                        .foregroundStyle(intensity.color)
                    Text(result?.explanation ?? String(localized: "Strain updates from heart rate and active energy as the day goes on."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
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
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: String(localized: "Today at a glance"))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                NavigationLink {
                    WeightView()
                } label: {
                    stat(
                        String(localized: "Weight · 7-day"),
                        value: weightKg.map { Formatters.kilograms($0) } ?? "—",
                        symbol: "scalemass.fill",
                        footnote: weightStatus.localizedName
                    )
                }
                .buttonStyle(.plain)
                stat(String(localized: "Steps"), value: steps.formatted(), symbol: "figure.walk")
                stat(String(localized: "Active"), value: Formatters.kcal(activeCalories), symbol: "flame.fill")
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
        BiceptionalCard(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                Text(value)
                    .font(Theme.display(20, weight: .semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                if let footnote {
                    Text(footnote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
