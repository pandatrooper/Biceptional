import Foundation

/// Duplicate of the app-side App Group payload so the widget target does not
/// depend on the iOS app module. Keep in sync with `Biceptional/Utilities/AppGroup.swift`.
enum AppGroup {
    static let identifier = "group.com.pandatrooper.Biceptional"
    static let snapshotKey = "todaySnapshot"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

struct TodaySnapshotPayload: Codable, Hashable, Sendable {
    var date: Date
    var recoveryScore: Double?
    var recoveryExplanation: String
    var sleepScore: Double?
    var sleepHours: Double?
    var strainScore: Double?
    var steps: Int
    var activeCalories: Double

    static let empty = TodaySnapshotPayload(
        date: .now,
        recoveryScore: nil,
        recoveryExplanation: "",
        sleepScore: nil,
        sleepHours: nil,
        strainScore: nil,
        steps: 0,
        activeCalories: 0
    )

    static func load() -> TodaySnapshotPayload {
        guard let data = AppGroup.defaults.data(forKey: AppGroup.snapshotKey),
              let payload = try? JSONDecoder().decode(TodaySnapshotPayload.self, from: data) else {
            return .empty
        }
        return payload
    }
}
