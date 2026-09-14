import Foundation

enum Formatters {
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    static let mediumDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()

    static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    static func hoursMinutes(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 {
            return String(localized: "\(minutes)m")
        }
        return String(localized: "\(hours)h \(minutes)m")
    }

    static func hours(_ hours: Double, fractionDigits: Int = 1) -> String {
        let formatted = hours.formatted(.number.precision(.fractionLength(fractionDigits)))
        return String(localized: "\(formatted)h")
    }

    static func kcal(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return String(localized: "\(rounded) kcal")
    }

    static func grams(_ value: Double, fractionDigits: Int = 0) -> String {
        let formatted = value.formatted(.number.precision(.fractionLength(fractionDigits)))
        return String(localized: "\(formatted) g")
    }

    static func kilograms(_ value: Double, fractionDigits: Int = 1) -> String {
        let formatted = value.formatted(.number.precision(.fractionLength(fractionDigits)))
        return String(localized: "\(formatted) kg")
    }

    static func bpm(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return String(localized: "\(rounded) bpm")
    }

    static func milliseconds(_ value: Double) -> String {
        let formatted = value.formatted(.number.precision(.fractionLength(0)))
        return String(localized: "\(formatted) ms")
    }
}
