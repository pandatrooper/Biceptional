import SwiftUI
import SwiftData
import HealthKit

struct WorkoutsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKit
    @Query(sort: \WorkoutRecord.startDate, order: .reverse) private var workouts: [WorkoutRecord]
    @State private var model = WorkoutViewModel()
    @State private var showLog = false

    var body: some View {
        NavigationStack {
            List {
                Picker(String(localized: "Filter"), selection: $model.filter) {
                    ForEach(WorkoutViewModel.WorkoutFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                let rows = workouts.filter(model.matches)
                if rows.isEmpty {
                    EmptyStateView(
                        systemImage: "figure.run",
                        title: String(localized: "No workouts yet"),
                        message: String(localized: "Log a session or wait for Apple Watch workouts to import from Health.")
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(rows, id: \.uuid) { workout in
                        NavigationLink {
                            WorkoutDetailView(workout: workout)
                        } label: {
                            WorkoutRow(workout: workout)
                        }
                        .listRowBackground(Color.cardFill)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.canvas)
            .navigationTitle(String(localized: "Workouts"))
            .searchable(text: $model.search, prompt: String(localized: "Exercise or activity"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showLog = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(String(localized: "Log Workout"))
                }
            }
            .sheet(isPresented: $showLog) {
                LogWorkoutView()
            }
            .refreshable {
                await ScoreRefreshService(healthKit: healthKit).importWorkouts(context: modelContext)
                try? modelContext.save()
            }
        }
    }
}

struct WorkoutRow: View {
    var workout: WorkoutRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(workout.name)
                    .font(.headline)
                Spacer()
                Text(workout.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Label(Formatters.hoursMinutes(workout.duration), systemImage: "clock")
                if let kcal = workout.activeEnergyKilocalories {
                    Label(Formatters.kcal(kcal), systemImage: "flame")
                }
                if !workout.sets.isEmpty {
                    Label(String(localized: "\(workout.sets.count) sets"), systemImage: "square.stack.3d.up")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct WorkoutDetailView: View {
    @Bindable var workout: WorkoutRecord

    var body: some View {
        List {
            Section(String(localized: "Session")) {
                LabeledContent(String(localized: "Duration"), value: Formatters.hoursMinutes(workout.duration))
                if let distance = workout.distanceMeters, distance > 0 {
                    LabeledContent(String(localized: "Distance"), value: (distance / 1000).formatted(.number.precision(.fractionLength(2))) + " km")
                }
                if let kcal = workout.activeEnergyKilocalories {
                    LabeledContent(String(localized: "Active energy"), value: Formatters.kcal(kcal))
                }
                if let avg = workout.averageHeartRate {
                    LabeledContent(String(localized: "Avg HR"), value: Formatters.bpm(avg))
                }
                if let max = workout.maxHeartRate {
                    LabeledContent(String(localized: "Max HR"), value: Formatters.bpm(max))
                }
                LabeledContent(String(localized: "Source"), value: workout.source == "healthKit" ? String(localized: "Apple Health") : String(localized: "Logged in Biceptional"))
            }

            if !workout.sets.isEmpty {
                Section(String(localized: "Sets")) {
                    ForEach(workout.sets.sorted { $0.setIndex < $1.setIndex }, id: \.uuid) { set in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(set.exerciseName)
                                    .font(.headline)
                                if set.supersetGroupID != nil {
                                    Text(String(localized: "Superset"))
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.orange.opacity(0.2), in: Capsule())
                                }
                                Spacer()
                                Text("\(set.reps) × \(Formatters.kilograms(set.weightKilograms))")
                                    .monospacedDigit()
                            }
                            Text(String(localized: "Rest \(set.restSeconds)s"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !set.notes.isEmpty {
                                Text(set.notes)
                                    .font(.footnote)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            if !workout.notes.isEmpty {
                Section(String(localized: "Notes")) {
                    Text(workout.notes)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.canvas)
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LogWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKit

    @State private var kind: Kind = .strength
    @State private var name = String(localized: "Strength")
    @State private var activity: HKWorkoutActivityType = .traditionalStrengthTraining
    @State private var start = Date.now.addingTimeInterval(-3600)
    @State private var end = Date.now
    @State private var durationMinutes = 60.0
    @State private var distanceKm = 0.0
    @State private var energy = 200.0
    @State private var notes = ""
    @State private var sets: [DraftSet] = [DraftSet()]
    @State private var logged = false
    @State private var errorMessage: String?

    enum Kind: String, CaseIterable, Identifiable {
        case strength, cardio
        var id: String { rawValue }
        var title: String {
            switch self {
            case .strength: String(localized: "Strength")
            case .cardio: String(localized: "Cardio")
            }
        }
    }

    struct DraftSet: Identifiable, Hashable {
        var id = UUID()
        var exerciseName = ""
        var reps = 8
        var weightKilograms = 20.0
        var restSeconds = 90
        var notes = ""
        var supersetWithPrevious = false
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker(String(localized: "Type"), selection: $kind) {
                    ForEach(Kind.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                TextField(String(localized: "Name"), text: $name)
                DatePicker(String(localized: "Start"), selection: $start)
                DatePicker(String(localized: "End"), selection: $end)

                if kind == .cardio {
                    cardioFields
                } else {
                    strengthFields
                }

                TextField(String(localized: "Notes"), text: $notes, axis: .vertical)
                    .lineLimit(3...6)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(String(localized: "Log Workout"))
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
            .onChange(of: kind) { _, newValue in
                if newValue == .cardio {
                    name = String(localized: "Run")
                    activity = .running
                } else {
                    name = String(localized: "Strength")
                    activity = .traditionalStrengthTraining
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var cardioFields: some View {
        Picker(String(localized: "Activity"), selection: $activity) {
            Text(String(localized: "Run")).tag(HKWorkoutActivityType.running)
            Text(String(localized: "Ride")).tag(HKWorkoutActivityType.cycling)
            Text(String(localized: "Walk")).tag(HKWorkoutActivityType.walking)
            Text(String(localized: "HIIT")).tag(HKWorkoutActivityType.highIntensityIntervalTraining)
            Text(String(localized: "Swim")).tag(HKWorkoutActivityType.swimming)
        }
        Stepper(value: $durationMinutes, in: 5...300, step: 5) {
            Text(String(localized: "Duration \(Int(durationMinutes)) min"))
        }
        TextField(String(localized: "Distance (km)"), value: $distanceKm, format: .number)
            .keyboardType(.decimalPad)
        TextField(String(localized: "Active kcal"), value: $energy, format: .number)
            .keyboardType(.decimalPad)
    }

    @ViewBuilder
    private var strengthFields: some View {
        ForEach($sets) { $set in
            Section {
                TextField(String(localized: "Exercise"), text: $set.exerciseName)
                Stepper(value: $set.reps, in: 1...50) {
                    Text(String(localized: "\(set.reps) reps"))
                }
                TextField(String(localized: "Weight (kg)"), value: $set.weightKilograms, format: .number)
                    .keyboardType(.decimalPad)
                Stepper(value: $set.restSeconds, in: 0...300, step: 15) {
                    Text(String(localized: "Rest \(set.restSeconds)s"))
                }
                Toggle(String(localized: "Superset with previous"), isOn: $set.supersetWithPrevious)
                TextField(String(localized: "Set notes"), text: $set.notes)
            }
        }
        Button(String(localized: "Add set")) {
            sets.append(DraftSet())
        }
    }

    private func save() async {
        if kind == .cardio {
            end = start.addingTimeInterval(durationMinutes * 60)
        }
        do {
            let hkUUID = try await healthKit.saveWorkout(
                activityType: activity,
                start: start,
                end: end,
                energyKilocalories: energy,
                distanceMeters: kind == .cardio ? distanceKm * 1000 : nil
            )
            let record = WorkoutRecord(
                healthKitUUID: hkUUID,
                source: "manual",
                name: name,
                activityTypeRaw: activity.rawValue,
                startDate: start,
                endDate: end,
                durationSeconds: end.timeIntervalSince(start),
                distanceMeters: kind == .cardio ? distanceKm * 1000 : nil,
                activeEnergyKilocalories: energy,
                notes: notes
            )
            if kind == .strength {
                var currentSuperset: UUID?
                for (index, draft) in sets.enumerated() {
                    if draft.supersetWithPrevious {
                        if currentSuperset == nil { currentSuperset = UUID() }
                    } else {
                        currentSuperset = nil
                    }
                    let set = StrengthSetEntry(
                        exerciseName: draft.exerciseName.isEmpty ? String(localized: "Exercise") : draft.exerciseName,
                        setIndex: index + 1,
                        reps: draft.reps,
                        weightKilograms: draft.weightKilograms,
                        restSeconds: draft.restSeconds,
                        notes: draft.notes,
                        supersetGroupID: currentSuperset
                    )
                    set.workout = record
                    record.sets.append(set)
                }
            }
            modelContext.insert(record)
            try modelContext.save()
            logged = true
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.warning()
        }
    }
}
