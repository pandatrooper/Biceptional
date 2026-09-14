import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]
    @State private var exportStart = Date.now.adding(days: -30)
    @State private var exportEnd = Date.now
    @State private var exportDocument = ExportDocument(text: "")
    @State private var showExporter = false
    private let notifications = NotificationService()

    private var prefs: UserPreferences {
        preferences.first ?? ScoreRefreshService.preferences(in: modelContext)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Sleep window")) {
                    Stepper(value: bind(\.sleepTargetMinHours), in: 5...10, step: 0.25) {
                        Text(String(localized: "Min \(prefs.sleepTargetMinHours.formatted(.number.precision(.fractionLength(2)))) h"))
                    }
                    Stepper(value: bind(\.sleepTargetMaxHours), in: 6...12, step: 0.25) {
                        Text(String(localized: "Max \(prefs.sleepTargetMaxHours.formatted(.number.precision(.fractionLength(2)))) h"))
                    }
                }

                Section(String(localized: "Nutrition targets")) {
                    stepper(title: String(localized: "Calories"), value: bind(\.calorieTarget), range: 1200...4000, step: 50, suffix: "kcal")
                    stepper(title: String(localized: "Protein"), value: bind(\.proteinTargetGrams), range: 60...250, step: 5, suffix: "g")
                    stepper(title: String(localized: "Carbs"), value: bind(\.carbTargetGrams), range: 50...450, step: 10, suffix: "g")
                    stepper(title: String(localized: "Fat"), value: bind(\.fatTargetGrams), range: 30...150, step: 5, suffix: "g")
                    stepper(title: String(localized: "Fiber"), value: bind(\.fiberTargetGrams), range: 10...60, step: 1, suffix: "g")
                }

                Section(String(localized: "Weight")) {
                    Stepper(value: bind(\.weightChangeTargetKgPerWeek), in: -1.5...1.5, step: 0.05) {
                        Text(String(localized: "Target \(prefs.weightChangeTargetKgPerWeek.formatted(.number.precision(.fractionLength(2)))) kg / week"))
                    }
                    Text(String(localized: "Negative is loss. Dashboard status compares the slope of your 7-day average to this number."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(String(localized: "Physiology")) {
                    Stepper(value: bindInt(\.ageYears), in: 16...80) {
                        Text(String(localized: "Age \(prefs.ageYears)"))
                    }
                    Text(String(localized: "Used only to estimate max heart rate for strain zones (Tanaka: 208 − 0.7 × age)."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(String(localized: "Notifications")) {
                    Toggle(String(localized: "Local reminders"), isOn: bind(\.notificationsEnabled))
                    Stepper(value: bindInt(\.morningRecoveryHour), in: 5...11) {
                        Text(String(localized: "Recovery alert \(prefs.morningRecoveryHour):00"))
                    }
                    Stepper(value: bindInt(\.weightReminderHour), in: 5...12) {
                        Text(String(localized: "Weight reminder \(prefs.weightReminderHour):00"))
                    }
                    Stepper(value: bindInt(\.foodReminderHour), in: 17...23) {
                        Text(String(localized: "Food reminder \(prefs.foodReminderHour):00"))
                    }
                }

                Section(String(localized: "Export")) {
                    DatePicker(String(localized: "From"), selection: $exportStart, displayedComponents: .date)
                    DatePicker(String(localized: "To"), selection: $exportEnd, displayedComponents: .date)
                    Button(String(localized: "Export CSV")) {
                        let csv = ExportService.csv(from: exportStart, to: exportEnd, context: modelContext)
                        exportDocument = ExportDocument(text: csv)
                        showExporter = true
                    }
                }

                Section(String(localized: "HealthKit")) {
                    Text(String(localized: "Biceptional stores computed scores, workouts, weight, and food on device in SwiftData. HealthKit is the source of physiology. Nothing is uploaded."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(String(localized: "Settings"))
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: .commaSeparatedText,
                defaultFilename: "biceptional-export"
            ) { _ in }
            .onChange(of: prefs.notificationsEnabled) { _, _ in
                Task { await notifications.reschedule(preferences: prefs) }
            }
            .onDisappear {
                try? modelContext.save()
                Task { await notifications.reschedule(preferences: prefs) }
            }
        }
    }

    private func stepper(title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, suffix: String) -> some View {
        Stepper(value: value, in: range, step: step) {
            Text("\(title) \(Int(value.wrappedValue)) \(suffix)")
        }
    }

    private func bind(_ keyPath: ReferenceWritableKeyPath<UserPreferences, Double>) -> Binding<Double> {
        Binding(
            get: { prefs[keyPath: keyPath] },
            set: { prefs[keyPath: keyPath] = $0 }
        )
    }

    private func bindInt(_ keyPath: ReferenceWritableKeyPath<UserPreferences, Int>) -> Binding<Int> {
        Binding(
            get: { prefs[keyPath: keyPath] },
            set: { prefs[keyPath: keyPath] = $0 }
        )
    }

    private func bind(_ keyPath: ReferenceWritableKeyPath<UserPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { prefs[keyPath: keyPath] },
            set: { prefs[keyPath: keyPath] = $0 }
        )
    }
}

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }
    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
