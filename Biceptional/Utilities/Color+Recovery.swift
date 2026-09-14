import SwiftUI

extension Color {
    /// Recovery / sleep / strain traffic-light using semantic system colors so
    /// they track Dark Mode and Increase Contrast rather than hardcoded hex.
    static func recoveryBand(_ score: Double?) -> Color {
        guard let score else { return .secondary }
        switch score {
        case 67...: return .green
        case 34..<67: return .orange
        default: return .red
        }
    }

    static func strainBand(_ strain: Double?) -> Color {
        guard let strain else { return .secondary }
        // 0–21 WHOOP-style scale.
        switch strain {
        case 14...: return .red
        case 8..<14: return .orange
        default: return .blue
        }
    }
}

enum RecoveryBand: String {
    case high
    case moderate
    case low
    case unknown

    init(score: Double?) {
        guard let score else {
            self = .unknown
            return
        }
        switch score {
        case 67...: self = .high
        case 34..<67: self = .moderate
        default: self = .low
        }
    }

    var localizedName: String {
        switch self {
        case .high: String(localized: "Green")
        case .moderate: String(localized: "Yellow")
        case .low: String(localized: "Red")
        case .unknown: String(localized: "Unknown")
        }
    }
}
