import SwiftUI
import Charts

struct RecoveryDetailView: View {
    var result: RecoveryResult?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BiceptionalCard {
                    VStack(spacing: 16) {
                        HeroRing(score: result?.score)
                            .frame(width: 200, height: 200)
                        Text(result?.explanation ?? String(localized: "No Recovery score yet."))
                            .font(Theme.coach)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }

                SectionLabel(text: String(localized: "Why this score"))
                if let components = result?.components {
                    BiceptionalCard {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(components) { component in
                                contributionRow(component)
                            }
                        }
                    }
                }

                SectionLabel(text: String(localized: "Formula"))
                BiceptionalCard {
                    Text(String(localized: "Recovery is a weighted blend of overnight HRV, resting heart rate, last night’s Sleep score, and respiratory rate — each scored as a z-score against your own 30-day baseline, then mapped to 0–100. Missing signals are dropped and the remaining weights are renormalized."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .background(Color.canvas.ignoresSafeArea())
        .navigationTitle(String(localized: "Recovery"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func contributionRow(_ component: RecoveryComponent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(component.name, systemImage: component.symbolName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(percent(component.weight))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.hairline)
                    Capsule()
                        .fill(Color.recoveryBand(component.score))
                        .frame(width: proxy.size.width * ((component.score ?? 0) / 100))
                }
            }
            .frame(height: 8)
            HStack {
                if let raw = component.rawValue {
                    Text("\(raw.formatted(.number.precision(.fractionLength(0...1)))) \(component.unitLabel)")
                }
                if let mean = component.baselineMean {
                    Text(String(localized: "baseline \(mean.formatted(.number.precision(.fractionLength(0...1))))"))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .font(.caption)
            .monospacedDigit()
            Text(component.note)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let z = component.zScore {
                Text(String(localized: "z \(z.formatted(.number.precision(.fractionLength(1))))"))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func percent(_ weight: Double) -> String {
        (weight * 100).formatted(.number.precision(.fractionLength(0))) + "%"
    }
}

struct SleepDetailView: View {
    var result: SleepResult?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BiceptionalCard {
                    HStack(alignment: .center, spacing: 16) {
                        HeroRing(score: result?.score)
                            .frame(width: 132, height: 132)
                        VStack(alignment: .leading, spacing: 8) {
                            if let night = result?.night {
                                labeled(String(localized: "Asleep"), Formatters.hours(night.asleepHours))
                                labeled(String(localized: "In bed"), Formatters.hoursMinutes(night.timeInBed))
                                labeled(String(localized: "Bed"), Formatters.shortTime.string(from: night.bedtime))
                                labeled(String(localized: "Wake"), Formatters.shortTime.string(from: night.wakeTime))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    if let explanation = result?.explanation {
                        Text(explanation)
                            .font(Theme.coach)
                            .padding(.top, 8)
                    }
                }

                if let night = result?.night, !night.stages.isEmpty {
                    SectionLabel(text: String(localized: "Hypnogram"))
                    BiceptionalCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HypnogramChart(night: night)
                                .frame(height: 180)
                            HStack {
                                Text(Formatters.shortTime.string(from: night.bedtime))
                                Spacer()
                                Text(Formatters.shortTime.string(from: night.wakeTime))
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            stageLegend(night)
                        }
                    }
                }

                if let components = result?.components {
                    SectionLabel(text: String(localized: "Breakdown"))
                    BiceptionalCard {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(components) { component in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(component.name)
                                        Spacer()
                                        Text(component.score.formatted(.number.precision(.fractionLength(0))))
                                            .monospacedDigit()
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    GeometryReader { proxy in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.hairline)
                                            Capsule()
                                                .fill(Color.recoveryBand(component.score))
                                                .frame(width: proxy.size.width * (component.score / 100))
                                        }
                                    }
                                    .frame(height: 8)
                                    Text(component.detail)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color.canvas.ignoresSafeArea())
        .navigationTitle(String(localized: "Sleep"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.subheadline)
    }

    private func stageLegend(_ night: SleepNight) -> some View {
        let asleep = max(night.totalAsleep, 1)
        return HStack(spacing: 12) {
            legend(.deep, night.duration(of: .deep) / asleep)
            legend(.core, night.duration(of: .core) / asleep)
            legend(.rem, night.duration(of: .rem) / asleep)
            legend(.awake, night.duration(of: .awake) / asleep)
        }
        .font(.caption)
    }

    private func legend(_ stage: SleepStage, _ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(Color.stage(stage)).frame(width: 8, height: 8)
                Text(stage.localizedName)
            }
            Text((fraction * 100).formatted(.number.precision(.fractionLength(0))) + "%")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HypnogramChart: View {
    var night: SleepNight

    var body: some View {
        Chart(night.stages) { interval in
            RectangleMark(
                xStart: .value(String(localized: "Start"), interval.start),
                xEnd: .value(String(localized: "End"), interval.end),
                y: .value(String(localized: "Stage"), interval.stage.localizedName)
            )
            .foregroundStyle(Color.stage(interval.stage))
        }
        .chartYScale(domain: [
            SleepStage.deep.localizedName,
            SleepStage.core.localizedName,
            SleepStage.rem.localizedName,
            SleepStage.awake.localizedName
        ])
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.hairline)
                AxisValueLabel()
            }
        }
        .chartLegend(.hidden)
        .accessibilityLabel(String(localized: "Sleep stage timeline"))
        .accessibilityValue(String(localized: "From \(Formatters.shortTime.string(from: night.bedtime)) to \(Formatters.shortTime.string(from: night.wakeTime))"))
    }
}
