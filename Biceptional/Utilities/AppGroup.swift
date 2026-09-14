import Foundation

/// App Group used to share today's scores with WidgetKit (and the watch, if
/// Watch Connectivity is unavailable). Must match the Xcode App Group capability.
enum AppGroup {
    static let identifier = "group.com.pandatrooper.Biceptional"
    static let snapshotKey = "todaySnapshot"
    static let lastRefreshKey = "lastHealthRefresh"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

/// Compact payload the widget and watch can decode without SwiftData.
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

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            AppGroup.defaults.set(data, forKey: AppGroup.snapshotKey)
            AppGroup.defaults.set(Date.now, forKey: AppGroup.lastRefreshKey)
        }
    }
}
