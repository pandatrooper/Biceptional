import SwiftUI
import SwiftData

struct NutritionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKit
    @Query(sort: \FoodEntry.loggedAt, order: .reverse) private var entries: [FoodEntry]
    @Query(sort: \CustomFood.lastUsedAt, order: .reverse) private var customFoods: [CustomFood]
    @State private var model = NutritionViewModel()
    @State private var showLog = false
    @State private var showCustom = false
    @State private var healthDay: DietaryDay?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summary
                }

                if let healthDay, healthDay.energyKilocalories > 0 {
                    Section(String(localized: "Apple Health")) {
                        Text(String(localized: "\(Formatters.kcal(healthDay.energyKilocalories)) · \(Formatters.grams(healthDay.proteinGrams)) protein already recorded by another app."))
                            .font(.footnote)
                        Toggle(String(localized: "Use Health totals for today"), isOn: $model.useHealthKitDay)
                    }
                }

                Section(String(localized: "Today")) {
                    let today = todayEntries
                    if today.isEmpty {
                        Text(String(localized: "Nothing logged yet."))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(today, id: \.uuid) { entry in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(entry.name)
                                    Text(entry.loggedAt.formatted(date: .omitted, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(Formatters.kcal(entry.calories))
                                    Text(Formatters.grams(entry.proteinGrams))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                        .onDelete(perform: delete)
                    }
                }

                if !customFoods.isEmpty {
                    Section(String(localized: "Frequent foods")) {
                        ForEach(customFoods.prefix(8), id: \.uuid) { food in
                            Button {
                                log(food)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(food.name)
                                        Text(String(localized: "\(Int(food.caloriesPerServing)) kcal · \(Int(food.proteinPerServing))g protein / \(food.servingLabel)"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .symbolRenderingMode(.hierarchical)
                                }
                            }
                            .accessibilityHint(String(localized: "Logs one serving"))
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Nutrition"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Custom food")) { showCustom = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showLog = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(String(localized: "Log Food"))
                }
            }
            .sheet(isPresented: $showLog) { LogFoodView() }
            .sheet(isPresented: $showCustom) { CustomFoodEditor() }
            .task { healthDay = await healthKit.dietaryDay(on: .now) }
        }
    }

    private var todayEntries: [FoodEntry] {
        let start = CalendarDay.start(of: .now)
        let end = CalendarDay.end(of: .now)
        return entries.filter { $0.loggedAt >= start && $0.loggedAt < end }
    }

    private var prefs: UserPreferences {
        ScoreRefreshService.preferences(in: modelContext)
    }

    private var totals: (kcal: Double, protein: Double, carbs: Double, fat: Double, fiber: Double) {
        if model.useHealthKitDay, let healthDay {
            return (healthDay.energyKilocalories, healthDay.proteinGrams, healthDay.carbsGrams, healthDay.fatGrams, healthDay.fiberGrams)
        }
        return todayEntries.reduce((0, 0, 0, 0, 0)) { partial, entry in
            (
                partial.0 + entry.calories,
                partial.1 + entry.proteinGrams,
                partial.2 + entry.carbsGrams,
                partial.3 + entry.fatGrams,
                partial.4 + entry.fiberGrams
            )
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            macroBar(String(localized: "Calories"), current: totals.kcal, target: prefs.calorieTarget, unit: "kcal")
            macroBar(String(localized: "Protein"), current: totals.protein, target: prefs.proteinTargetGrams, unit: "g")
            macroBar(String(localized: "Carbs"), current: totals.carbs, target: prefs.carbTargetGrams, unit: "g")
            macroBar(String(localized: "Fat"), current: totals.fat, target: prefs.fatTargetGrams, unit: "g")
            macroBar(String(localized: "Fiber"), current: totals.fiber, target: prefs.fiberTargetGrams, unit: "g")
        }
        .accessibilityElement(children: .combine)
    }

    private func macroBar(_ title: String, current: Double, target: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(current)) / \(Int(target)) \(unit)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            ProgressView(value: target > 0 ? min(current / target, 1.2) : 0)
                .tint(current > target * 1.05 ? .orange : .accentColor)
        }
    }

    private func log(_ food: CustomFood) {
        let macros = food.macros(servings: 1)
        let entry = FoodEntry(
            name: food.name,
            calories: macros.kcal,
            proteinGrams: macros.protein,
            carbsGrams: macros.carbs,
            fatGrams: macros.fat,
            fiberGrams: macros.fiber,
            servings: 1,
            customFoodID: food.uuid
        )
        modelContext.insert(entry)
        food.useCount += 1
        food.lastUsedAt = .now
        try? modelContext.save()
        Haptics.success()
        Task { try? await healthKit.saveDietary(entry: entry) }
    }

    private func delete(at offsets: IndexSet) {
        let today = todayEntries
        for index in offsets {
            modelContext.delete(today[index])
        }
        try? modelContext.save()
    }
}

struct LogFoodView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKit
    @Query(sort: \CustomFood.lastUsedAt, order: .reverse) private var foods: [CustomFood]
    @State private var model = NutritionViewModel()
    @State private var selectedFoodID: UUID?
    @State private var errorMessage: String?

    private var selectedFood: CustomFood? {
        foods.first { $0.uuid == selectedFoodID }
    }

    var body: some View {
        NavigationStack {
            Form {
                if !foods.isEmpty {
                    Picker(String(localized: "Recent"), selection: $selectedFoodID) {
                        Text(String(localized: "New entry")).tag(Optional<UUID>.none)
                        ForEach(foods, id: \.uuid) { food in
                            Text(food.name).tag(Optional(food.uuid))
                        }
                    }
                }

                Toggle(String(localized: "Log by grams"), isOn: $model.logByGrams)

                TextField(String(localized: "Name"), text: $model.draftName)

                if model.logByGrams {
                    TextField(String(localized: "Grams"), value: $model.draftGrams, format: .number)
                        .keyboardType(.decimalPad)
                } else {
                    TextField(String(localized: "Servings"), value: $model.draftServings, format: .number)
                        .keyboardType(.decimalPad)
                }

                if selectedFood == nil {
                    TextField(String(localized: "Calories"), value: $model.draftCalories, format: .number)
                    TextField(String(localized: "Protein (g)"), value: $model.draftProtein, format: .number)
                    TextField(String(localized: "Carbs (g)"), value: $model.draftCarbs, format: .number)
                    TextField(String(localized: "Fat (g)"), value: $model.draftFat, format: .number)
                    TextField(String(localized: "Fiber (g)"), value: $model.draftFiber, format: .number)
                } else if let selectedFood {
                    Text(previewMacros(selectedFood))
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle(String(localized: "Log Food"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) { Task { await save() } }
                        .fontWeight(.semibold)
                }
            }
            .sensoryFeedback(.success, trigger: model.didLog)
            .onChange(of: selectedFoodID) { _, id in
                if let food = foods.first(where: { $0.uuid == id }) {
                    model.draftName = food.name
                }
            }
        }
        .presentationDetents([.large])
    }

    private func previewMacros(_ food: CustomFood) -> String {
        let macros: (kcal: Double, protein: Double, carbs: Double, fat: Double, fiber: Double)
        if model.logByGrams {
            let result = food.macros(grams: model.draftGrams)
            macros = (result.kcal, result.protein, result.carbs, result.fat, result.fiber)
        } else {
            macros = food.macros(servings: model.draftServings)
        }
        return "\(Int(macros.kcal)) kcal · \(Int(macros.protein))g P · \(Int(macros.carbs))g C · \(Int(macros.fat))g F"
    }

    private func save() async {
        var calories = model.draftCalories
        var protein = model.draftProtein
        var carbs = model.draftCarbs
        var fat = model.draftFat
        var fiber = model.draftFiber
        var grams = model.logByGrams ? model.draftGrams : nil
        var servings = model.draftServings
        var customID: UUID?

        if let food = selectedFood {
            if model.logByGrams {
                let result = food.macros(grams: model.draftGrams)
                calories = result.kcal
                protein = result.protein
                carbs = result.carbs
                fat = result.fat
                fiber = result.fiber
                servings = result.servings
                grams = model.draftGrams
            } else {
                let result = food.macros(servings: model.draftServings)
                calories = result.kcal
                protein = result.protein
                carbs = result.carbs
                fat = result.fat
                fiber = result.fiber
            }
            customID = food.uuid
            food.useCount += 1
            food.lastUsedAt = .now
        }

        let entry = FoodEntry(
            name: model.draftName.isEmpty ? String(localized: "Food") : model.draftName,
            calories: calories,
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat,
            fiberGrams: fiber,
            grams: grams,
            servings: servings,
            customFoodID: customID
        )
        modelContext.insert(entry)
        try? modelContext.save()
        do {
            try await healthKit.saveDietary(entry: entry)
        } catch {
            errorMessage = error.localizedDescription
        }
        model.didLog = true
        Haptics.success()
        dismiss()
    }
}

struct CustomFoodEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomFood.name) private var foods: [CustomFood]
    @State private var name = ""
    @State private var calories = 250.0
    @State private var protein = 12.0
    @State private var carbs = 30.0
    @State private var fat = 8.0
    @State private var fiber = 4.0
    @State private var servingGrams = 100.0
    @State private var servingLabel = String(localized: "bowl")

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "New homemade food")) {
                    TextField(String(localized: "Name"), text: $name)
                    TextField(String(localized: "Serving label"), text: $servingLabel)
                    TextField(String(localized: "Grams per serving"), value: $servingGrams, format: .number)
                        .keyboardType(.decimalPad)
                    TextField(String(localized: "Calories / serving"), value: $calories, format: .number)
                    TextField(String(localized: "Protein (g)"), value: $protein, format: .number)
                    TextField(String(localized: "Carbs (g)"), value: $carbs, format: .number)
                    TextField(String(localized: "Fat (g)"), value: $fat, format: .number)
                    TextField(String(localized: "Fiber (g)"), value: $fiber, format: .number)
                    Button(String(localized: "Save food")) {
                        let food = CustomFood(
                            name: name,
                            caloriesPerServing: calories,
                            proteinPerServing: protein,
                            carbsPerServing: carbs,
                            fatPerServing: fat,
                            fiberPerServing: fiber,
                            servingSizeGrams: servingGrams,
                            servingLabel: servingLabel
                        )
                        modelContext.insert(food)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section(String(localized: "Saved")) {
                    ForEach(foods, id: \.uuid) { food in
                        VStack(alignment: .leading) {
                            Text(food.name)
                            Text(String(localized: "\(Int(food.caloriesPerServing)) kcal / \(food.servingLabel) (\(Int(food.servingSizeGrams)) g)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            modelContext.delete(foods[index])
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Custom foods"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
    }
}
