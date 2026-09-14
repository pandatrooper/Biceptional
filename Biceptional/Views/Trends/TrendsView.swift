import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model = TrendsViewModel()
    @State private var metric: Metric = .recovery

    enum Metric: String, CaseIterable, Identifiable {
        case recovery, sleep, strain, weight, nutrition
        var id: String { rawValue }
        var title: String {
            switch self {
            case .recovery: String(localized: "Recovery")
            case .sleep: String(localized: "Sleep")
            case .strain: String(localized: "Strain")
            case .weight: String(localized: "Weight")
            case .nutrition: String(localized: "Nutrition")
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(String(localized: "Metric"), selection: $metric) {
                        ForEach(Metric.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    chart
                        .frame(height: 220)
                }

                Section(String(localized: "Correlations")) {
                    correlation(
                        String(localized: "Sleep duration vs. next-day Recovery"),
                        value: model.sleepVsRecovery,
                        hint: String(localized: "Positive means more sleep tends to raise Recovery the next morning.")
                    )
                    correlation(
                        String(localized: "Strain vs. next-day Recovery"),
                        value: model.strainVsRecovery,
                        hint: String(localized: "Negative means harder days tend to suppress Recovery the next morning.")
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.canvas)
            .navigationTitle(String(localized: "Trends"))
            .onAppear { model.load(context: modelContext) }
        }
    }

    @ViewBuilder
    private var chart: some View {
        let points = model.points
        Chart(points) { point in
            switch metric {
            case .recovery:
                if let value = point.recovery {
                    LineMark(x: .value("Day", point.day), y: .value("Recovery", value))
                        .foregroundStyle(Color.recoveryGreen)
                }
            case .sleep:
                if let value = point.sleep {
                    LineMark(x: .value("Day", point.day), y: .value("Sleep", value))
                        .foregroundStyle(Color.stageREM)
                }
            case .strain:
                if let value = point.strain {
                    BarMark(x: .value("Day", point.day), y: .value("Strain", value))
                        .foregroundStyle(Color.strainMid)
                }
            case .weight:
                if let value = point.weightKg {
                    LineMark(x: .value("Day", point.day), y: .value("kg", value))
                }
            case .nutrition:
                if let value = point.calories {
                    BarMark(x: .value("Day", point.day), y: .value("kcal", value))
                }
            }
        }
        .chartYScale(domain: metric == .weight ? .automatic(includesZero: false) : .automatic)
        .accessibilityLabel(metric.title)
    }

    private func correlation(_ title: String, value: Double?, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text(hint)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
