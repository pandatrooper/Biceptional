import Foundation

/// One Recovery input after z-score mapping, used both for the 0–100 score
/// and the explainability UI ("% contribution").
struct RecoveryComponent: Hashable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    var symbolName: String
    /// Weight after missing-signal renormalization (sums to 1.0).
    var weight: Double
    /// 0–100 component score. `nil` if this signal was unavailable.
    var score: Double?
    /// Signed z-score vs. the user's 30-day baseline. Positive = better recovery.
    var zScore: Double?
    var rawValue: Double?
    var baselineMean: Double?
    var unitLabel: String
    var note: String

    var contribution: Double {
        (score ?? 0) * weight
    }
}

struct RecoveryResult: Hashable, Sendable {
    var score: Double?
    var components: [RecoveryComponent]
    var explanation: String
    var usedLimitedData: Bool

    var band: RecoveryBand { RecoveryBand(score: score) }
}

struct SleepStageInterval: Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var start: Date
    var end: Date
    var stage: SleepStage

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

enum SleepStage: String, Codable, Hashable, Sendable, CaseIterable {
    case inBed
    case awake
    case asleepUnspecified
    case core
    case deep
    case rem

    var localizedName: String {
        switch self {
        case .inBed: String(localized: "In bed")
        case .awake: String(localized: "Awake")
        case .asleepUnspecified: String(localized: "Asleep")
        case .core: String(localized: "Core")
        case .deep: String(localized: "Deep")
        case .rem: String(localized: "REM")
        }
    }

    var symbolName: String {
        switch self {
        case .inBed: "bed.double"
        case .awake: "eye"
        case .asleepUnspecified: "moon.zzz"
        case .core: "zzz"
        case .deep: "moon.fill"
        case .rem: "brain.head.profile"
        }
    }

    /// Chart / VoiceOver order from deepest to lightest.
    var plotRank: Int {
        switch self {
        case .deep: 0
        case .core, .asleepUnspecified: 1
        case .rem: 2
        case .awake: 3
        case .inBed: 4
        }
    }
}

struct SleepNight: Hashable, Sendable, Identifiable {
    var id: Date { morning }
    /// Calendar day this night "belongs" to (the morning you woke up).
    var morning: Date
    var bedtime: Date
    var wakeTime: Date
    var totalAsleep: TimeInterval
    var timeInBed: TimeInterval
    var stages: [SleepStageInterval]
    var hasStaging: Bool

    var asleepHours: Double { totalAsleep / 3600 }

    func duration(of stage: SleepStage) -> TimeInterval {
        stages.filter { $0.stage == stage }.reduce(0) { $0 + $1.duration }
    }
}

struct SleepComponent: Hashable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    var weight: Double
    var score: Double
    var detail: String
}

struct SleepResult: Hashable, Sendable {
    var score: Double?
    var night: SleepNight?
    var components: [SleepComponent]
    var explanation: String
}

struct HeartRateZoneMinutes: Hashable, Sendable {
    var zone1: Double
    var zone2: Double
    var zone3: Double
    var zone4: Double
    var zone5: Double

    var total: Double { zone1 + zone2 + zone3 + zone4 + zone5 }
}

struct StrainResult: Hashable, Sendable {
    /// 0–21 WHOOP-style cardiovascular load.
    var score: Double
    var load: Double
    var personalMaxLoad: Double
    var zoneMinutes: HeartRateZoneMinutes
    var activeEnergyKilocalories: Double
    var explanation: String
}

struct OvernightPhysiology: Hashable, Sendable {
    var hrvSDNN: Double?
    var restingHeartRate: Double?
    var respiratoryRate: Double?
    var oxygenSaturation: Double?
}

struct BaselineStats: Hashable, Sendable {
    var mean: Double
    var standardDeviation: Double
    var sampleCount: Int

    static func from(_ values: [Double], fallbackSD: Double) -> BaselineStats? {
        let cleaned = values.filter { $0.isFinite }
        guard !cleaned.isEmpty else { return nil }
        let mean = cleaned.reduce(0, +) / Double(cleaned.count)
        let sd: Double
        if cleaned.count >= 2 {
            let variance = cleaned.reduce(0) { $0 + pow($1 - mean, 2) } / Double(cleaned.count - 1)
            sd = max(sqrt(variance), fallbackSD * 0.25)
        } else {
            sd = fallbackSD
        }
        return BaselineStats(mean: mean, standardDeviation: sd, sampleCount: cleaned.count)
    }
}

struct DailyActivityTotals: Hashable, Sendable {
    var steps: Int
    var distanceMeters: Double
    var activeEnergyKilocalories: Double
    var basalEnergyKilocalories: Double
    var vo2Max: Double?
}

struct DietaryDay: Hashable, Sendable {
    var energyKilocalories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var fiberGrams: Double
    var sourceLabel: String
}

enum WeightTrendStatus: String, Codable, Sendable {
    case losingFast
    case onTrack
    case flat
    case gainingFast
    case unknown

    var localizedName: String {
        switch self {
        case .losingFast: String(localized: "Losing fast")
        case .onTrack: String(localized: "On track")
        case .flat: String(localized: "Flat")
        case .gainingFast: String(localized: "Gaining fast")
        case .unknown: String(localized: "No trend yet")
        }
    }
}
