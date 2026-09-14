import SwiftUI
import Charts

struct RecoveryDetailView: View {
    var result: RecoveryResult?

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    ScoreRing(score: result?.score, color: .recoveryBand(result?.score))
                        .frame(width: 160, height: 160)
                        .padding(.vertical)
                    Spacer()
                }
                .listRowBackground(Color.clear)
                Text(result?.explanation ?? String(localized: "No Recovery score yet."))
                    .font(.body)
            }

            Section(String(localized: "Why this score")) {
                if let components = result?.components {
                    ForEach(components) { component in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(component.name, systemImage: component.symbolName)
                                Spacer()
                                Text(percent(component.weight))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            ProgressView(value: (component.score ?? 0) / 100)
                                .tint(Color.recoveryBand(component.score))
                            HStack {
                                if let raw = component.rawValue {
                                    Text("\(raw.formatted(.number.precision(.fractionLength(0...1)))) \(component.unitLabel)")
                                }
                                if let mean = component.baselineMean {
                                    Text(String(localized: "baseline \(mean.formatted(.number.precision(.fractionLength(0...1))))"))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let z = component.zScore {
                                    Text(String(localized: "z \(z.formatted(.number.precision(.fractionLength(1))))"))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption)
                            Text(component.note)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            Section(String(localized: "Formula")) {
                Text(String(localized: "Recovery is a weighted blend of overnight HRV, resting heart rate, last night’s Sleep score, and respiratory rate — each scored as a z-score against your own 30-day baseline, then mapped to 0–100. Missing signals are dropped and the remaining weights are renormalized. Details live in ScoringEngine.swift."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(String(localized: "Recovery"))
        .navigationBarTitleDisplayMode(.inline)
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
                HStack {
                    ScoreRing(score: result?.score, color: .recoveryBand(result?.score))
                        .frame(width: 140, height: 140)
                    VStack(alignment: .leading, spacing: 6) {
                        if let night = result?.night {
                            labeled(String(localized: "Asleep"), Formatters.hours(night.asleepHours))
                            labeled(String(localized: "In bed"), Formatters.hoursMinutes(night.timeInBed))
                            labeled(String(localized: "Bed"), Formatters.shortTime.string(from: night.bedtime))
                            labeled(String(localized: "Wake"), Formatters.shortTime.string(from: night.wakeTime))
                        }
                    }
                    Spacer()
                }

                Text(result?.explanation ?? "")
                    .font(.body)

                if let night = result?.night, !night.stages.isEmpty {
                    Text(String(localized: "Hypnogram"))
                        .font(.headline)
                    HypnogramChart(night: night)
                        .frame(height: 180)
                    stageLegend(night)
                }

                if let components = result?.components {
                    ForEach(components) { component in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(component.name)
                                Spacer()
                                Text(component.score.formatted(.number.precision(.fractionLength(0))))
                                    .monospacedDigit()
                            }
                            .font(.subheadline.weight(.semibold))
                            ProgressView(value: component.score / 100)
                            Text(component.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
        }
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
        VStack(alignment: .leading) {
            Text(stage.localizedName)
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
            .foregroundStyle(by: .value(String(localized: "Stage"), interval.stage.localizedName))
        }
        .chartYScale(domain: [
            SleepStage.deep.localizedName,
            SleepStage.core.localizedName,
            SleepStage.rem.localizedName,
            SleepStage.awake.localizedName
        ])
        .chartLegend(.hidden)
        .accessibilityLabel(String(localized: "Sleep stage timeline"))
        .accessibilityValue(String(localized: "From \(Formatters.shortTime.string(from: night.bedtime)) to \(Formatters.shortTime.string(from: night.wakeTime))"))
    }
}
