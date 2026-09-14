import Foundation

enum CalendarDay {
    static func start(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    static func end(of date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? date
    }

    /// Sleep "night" for a calendar morning: previous noon → this noon.
    static func overnightWindow(endingOnMorning date: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let morning = calendar.startOfDay(for: date)
        let noon = calendar.date(byAdding: .hour, value: 12, to: morning) ?? morning
        let previousNoon = calendar.date(byAdding: .day, value: -1, to: noon) ?? noon
        return (previousNoon, noon)
    }

    static func range(endingOn end: Date, days: Int, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let endOfDay = self.end(of: end, calendar: calendar)
        let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: end)) ?? end
        return (start, endOfDay)
    }
}

extension Date {
    var startOfDay: Date { CalendarDay.start(of: self) }

    func adding(days: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: days, to: self) ?? self
    }
}
