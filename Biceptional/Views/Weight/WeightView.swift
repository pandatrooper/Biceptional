import SwiftUI
import SwiftData
import Charts

struct WeightView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKit
    @Query(sort: \WeightSample.date) private var samples: [WeightSample]
    @State private var model = WeightViewModel()
    @State private var showLog = false

    var body: some View {
            List {
                Section {
                    Picker(String(localized: "Range"), selection: $model.range) {
                        ForEach(WeightViewModel.ChartRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)

                    WeightChart(samples: filtered, rolling: rolling)
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 8))
                }

                Section {
                    LabeledContent(String(localized: "7-day average")) {
                        Text(rolling.last.map { Formatters.kilograms($0.kg) } ?? "—")
                    }
                    LabeledContent(String(localized: "Trend")) {
                        Text(status.localizedName)
                    }
                    if let slope {
                        LabeledContent(String(localized: "Slope")) {
                            Text(String(localized: "\(slope.formatted(.number.precision(.fractionLength(2)))) kg/week"))
                        }
                    }
                } footer: {
                    Text(String(localized: "The 7-day rolling average is the number to trust. Daily weigh-ins stay on the chart as a faint series."))
                }

                Section(String(localized: "History")) {
                    ForEach(filtered.reversed(), id: \.uuid) { sample in
                        HStack {
                            Text(sample.date.formatted(date: .abbreviated, time: .shortened))
                            Spacer()
                            Text(Formatters.kilograms(sample.kilograms))
                                .monospacedDigit()
                            Text(sample.source == "healthKit" ? String(localized: "Health") : String(localized: "Manual"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Weight"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showLog = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(String(localized: "Log Weight"))
                }
            }
            .sheet(isPresented: $showLog) {
                LogWeightView()
            }
    }

    private var filtered: [WeightSample] {
        guard let days = model.range.days else { return samples }
        let start = Date.now.adding(days: -days)
        return samples.filter { $0.date >= start }
    }

    private var rolling: [(date: Date, kg: Double)] {
        let daily = Dictionary(filtered.map { (CalendarDay.start(of: $0.date), $0.kilograms) }, uniquingKeysWith: { _, last in last })
        let points = daily.keys.sorted().map { (date: $0, kg: daily[$0]!) }
        return ScoringEngine.rollingAverage(values: points)
    }

    private var slope: Double? {
        ScoringEngine.weeklySlopeKg(rolling: rolling)
    }

    private var status: WeightTrendStatus {
        let prefs = ScoreRefreshService.preferences(in: modelContext)
        return ScoringEngine.weightStatus(slopeKgPerWeek: slope, targetKgPerWeek: prefs.weightChangeTargetKgPerWeek)
    }
}

struct WeightChart: View {
    var samples: [WeightSample]
    var rolling: [(date: Date, kg: Double)]

    private struct RollingPoint: Identifiable {
        var id: Date { date }
        var date: Date
        var kg: Double
    }

    var body: some View {
        Chart {
            ForEach(samples, id: \.uuid) { sample in
                PointMark(
                    x: .value(String(localized: "Day"), sample.date),
                    y: .value(String(localized: "kg"), sample.kilograms)
                )
                .foregroundStyle(.secondary.opacity(0.35))
                .symbolSize(16)
            }
            ForEach(rolling.map { RollingPoint(date: $0.date, kg: $0.kg) }) { point in
                LineMark(
                    x: .value(String(localized: "Day"), point.date),
                    y: .value(String(localized: "kg"), point.kg)
                )
                .foregroundStyle(Color.primary)
                .interpolationMethod(.catmullRom)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityLabel(String(localized: "Weight trend"))
    }
}

struct LogWeightView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKit
    @State private var kilograms = 70.0
    @State private var date = Date.now
    @State private var logged = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField(String(localized: "Weight (kg)"), value: $kilograms, format: .number.precision(.fractionLength(1)))
                    .keyboardType(.decimalPad)
                    .font(.largeTitle.monospacedDigit())
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(String(localized: "Body weight in kilograms"))
                DatePicker(String(localized: "When"), selection: $date)
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle(String(localized: "Log Weight"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        Task { await save() }
                    }
                    .fontWeight(.semibold)
                }
            }
            .sensoryFeedback(.success, trigger: logged)
            .onAppear {
                if let last = (try? modelContext.fetch(FetchDescriptor<WeightSample>()))?.max(by: { $0.date < $1.date }) {
                    kilograms = last.kilograms
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        do {
            try await healthKit.saveBodyMass(kilograms: kilograms, date: date)
            modelContext.insert(WeightSample(date: date, kilograms: kilograms, source: "manual"))
            try modelContext.save()
            logged = true
            dismiss()
        } catch {
            // Still persist locally if Health write is denied.
            modelContext.insert(WeightSample(date: date, kilograms: kilograms, source: "manual"))
            try? modelContext.save()
            errorMessage = error.localizedDescription
            logged = true
            Haptics.success()
            dismiss()
        }
    }
}
