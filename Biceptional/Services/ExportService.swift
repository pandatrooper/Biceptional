import Foundation
import SwiftData
import SwiftUI

/// CSV export of daily scores, workouts, weight, and food for a date range.
/// Personal-use off-ramp — everything lives on device until you share it.
enum ExportService {
    static func csv(
        from start: Date,
        to end: Date,
        context: ModelContext
    ) -> String {
        let startDay = CalendarDay.start(of: start)
        let endDay = CalendarDay.end(of: end)

        let snapshots = ((try? context.fetch(FetchDescriptor<DailySnapshot>())) ?? [])
            .filter { $0.day >= startDay && $0.day < endDay }
            .sorted { $0.day < $1.day }
        let workouts = ((try? context.fetch(FetchDescriptor<WorkoutRecord>())) ?? [])
            .filter { $0.startDate >= startDay && $0.startDate < endDay }
            .sorted { $0.startDate < $1.startDate }
        let weights = ((try? context.fetch(FetchDescriptor<WeightSample>())) ?? [])
            .filter { $0.date >= startDay && $0.date < endDay }
            .sorted { $0.date < $1.date }
        let foods = ((try? context.fetch(FetchDescriptor<FoodEntry>())) ?? [])
            .filter { $0.loggedAt >= startDay && $0.loggedAt < endDay }
            .sorted { $0.loggedAt < $1.loggedAt }

        var lines: [String] = []
        lines.append("# Biceptional export")
        lines.append("# \(startDay.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))")
        lines.append("")
        lines.append("## Daily scores")
        lines.append("date,recovery,sleep,sleep_hours,strain,steps,active_kcal,hrv_sdnn,rhr")
        for row in snapshots {
            lines.append([
                isoDay(row.day),
                n(row.recoveryScore),
                n(row.sleepScore),
                n(row.sleepHours),
                n(row.strainScore),
                String(row.steps),
                n(row.activeCalories),
                n(row.hrvSDNN),
                n(row.restingHeartRate)
            ].joined(separator: ","))
        }
        lines.append("")
        lines.append("## Workouts")
        lines.append("start,end,name,source,duration_s,distance_m,kcal,avg_hr,max_hr,notes")
        for row in workouts {
            lines.append([
                iso(row.startDate),
                iso(row.endDate),
                csvEscape(row.name),
                row.source,
                n(row.durationSeconds),
                n(row.distanceMeters),
                n(row.activeEnergyKilocalories),
                n(row.averageHeartRate),
                n(row.maxHeartRate),
                csvEscape(row.notes)
            ].joined(separator: ","))
        }
        lines.append("")
        lines.append("## Weight")
        lines.append("date,kg,source")
        for row in weights {
            lines.append([iso(row.date), n(row.kilograms), row.source].joined(separator: ","))
        }
        lines.append("")
        lines.append("## Food")
        lines.append("logged_at,name,kcal,protein_g,carbs_g,fat_g,fiber_g,grams,servings,source")
        for row in foods {
            lines.append([
                iso(row.loggedAt),
                csvEscape(row.name),
                n(row.calories),
                n(row.proteinGrams),
                n(row.carbsGrams),
                n(row.fatGrams),
                n(row.fiberGrams),
                n(row.grams),
                n(row.servings),
                row.source
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func isoDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func n(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
