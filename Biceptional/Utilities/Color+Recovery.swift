import SwiftUI

extension Color {
    static func recoveryBand(_ score: Double?) -> Color {
        RecoveryBand(score: score).color
    }

    static func strainBand(_ strain: Double?) -> Color {
        StrainIntensity(score: strain).color
    }

    static func stage(_ stage: SleepStage) -> Color {
        switch stage {
        case .deep: .stageDeep
        case .core, .asleepUnspecified: .stageCore
        case .rem: .stageREM
        case .awake: .stageAwake
        case .inBed: .hairline
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

    var color: Color {
        switch self {
        case .high: .recoveryGreen
        case .moderate: .recoveryYellow
        case .low: .recoveryRed
        case .unknown: .secondary
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

    var chipTitle: String {
        localizedName.uppercased()
    }
}

enum StrainIntensity {
    case light
    case moderate
    case high
    case unknown

    init(score: Double?) {
        guard let score else {
            self = .unknown
            return
        }
        switch score {
        case 14...: self = .high
        case 8..<14: self = .moderate
        default: self = .light
        }
    }

    var color: Color {
        switch self {
        case .light: .strainLow
        case .moderate: .strainMid
        case .high: .strainHigh
        case .unknown: .secondary
        }
    }

    var localizedName: String {
        switch self {
        case .light: String(localized: "Light")
        case .moderate: String(localized: "Moderate")
        case .high: String(localized: "High")
        case .unknown: String(localized: "None")
        }
    }
}

enum Theme {
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static var sectionLabel: Font { .caption.weight(.semibold) }

    static var coach: Font { .callout }

    static var score: Font { display(44) }
}

struct SectionLabel: View {
    var text: String

    var body: some View {
        Text(text.uppercased())
            .font(Theme.sectionLabel)
            .tracking(1.2)
            .foregroundStyle(.secondary)
    }
}

struct BiceptionalScreen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .scrollContentBackground(.hidden)
            .background(Color.canvas.ignoresSafeArea())
    }
}
