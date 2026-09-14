import Foundation

/// Recovery, Sleep, and Strain math.
///
/// WHOOP's exact formulas are proprietary. These approximations follow the
/// same *ideas* (personal z-scores, overnight physiology, cardiovascular load)
/// that show up in the open HRV-readiness literature. They never compare the
/// user to a population nomogram — every z-score is against *their* rolling
/// 30-day baseline.
enum ScoringEngine {

    // MARK: - Recovery (0–100)

    /// Default contribution of each Recovery input. Missing signals have their
    /// weight redistributed so the remaining inputs still sum to 1.0.
    enum RecoveryWeight {
        static let hrv = 0.40
        static let restingHR = 0.30
        static let sleep = 0.25
        static let respiratory = 0.05
    }

    /// Maps a signed z-score onto 0–100.
    ///
    /// - z = 0  → 50  (a typical night vs. your own baseline)
    /// - z = +2 → 80  (unusually recovered)
    /// - z = −2 → 20  (unusually strained)
    ///
    /// Slope of 15 points per SD is a deliberate choice: three SDs in either
    /// direction saturate the scale without a single noisy night pinning at 0 or 100.
    static func componentScore(z: Double) -> Double {
        clamp(50 + 15 * z, 0, 100)
    }

    static func recovery(
        physiology: OvernightPhysiology,
        hrvBaseline: BaselineStats?,
        rhrBaseline: BaselineStats?,
        rrBaseline: BaselineStats?,
        sleepScore: Double?
    ) -> RecoveryResult {
        var components: [RecoveryComponent] = []

        // HRV: higher than your baseline is better recovery.
        components.append(
            makeComponent(
                name: String(localized: "HRV"),
                symbol: "waveform.path.ecg",
                defaultWeight: RecoveryWeight.hrv,
                value: physiology.hrvSDNN,
                baseline: hrvBaseline,
                invert: false,
                unit: "ms",
                higherIsBetterNote: String(localized: "Overnight SDNN vs. your 30-day baseline. Higher HRV than usual is a positive recovery signal.")
            )
        )

        // RHR: lower than your baseline is better recovery.
        components.append(
            makeComponent(
                name: String(localized: "Resting HR"),
                symbol: "heart.fill",
                defaultWeight: RecoveryWeight.restingHR,
                value: physiology.restingHeartRate,
                baseline: rhrBaseline,
                invert: true,
                unit: "bpm",
                higherIsBetterNote: String(localized: "Morning resting heart rate vs. your 30-day baseline. A rise usually means you are not fully recovered.")
            )
        )

        let sleepComponent: RecoveryComponent
        if let sleepScore {
            // Sleep is already 0–100. Convert to a z-like score around 70 so a
            // "good enough" night is roughly the Recovery midpoint.
            let z = (sleepScore - 70) / 15
            sleepComponent = RecoveryComponent(
                name: String(localized: "Sleep"),
                symbolName: "moon.zzz.fill",
                weight: RecoveryWeight.sleep,
                score: sleepScore,
                zScore: z,
                rawValue: sleepScore,
                baselineMean: 70,
                unitLabel: "pts",
                note: String(localized: "Last night's Sleep score. Duration, consistency, and stages (when available).")
            )
        } else {
            sleepComponent = RecoveryComponent(
                name: String(localized: "Sleep"),
                symbolName: "moon.zzz.fill",
                weight: RecoveryWeight.sleep,
                score: nil,
                zScore: nil,
                rawValue: nil,
                baselineMean: nil,
                unitLabel: "pts",
                note: String(localized: "No sleep samples for last night.")
            )
        }
        components.append(sleepComponent)

        components.append(
            makeComponent(
                name: String(localized: "Respiratory rate"),
                symbol: "lungs.fill",
                defaultWeight: RecoveryWeight.respiratory,
                value: physiology.respiratoryRate,
                baseline: rrBaseline,
                invert: true,
                unit: "brpm",
                higherIsBetterNote: String(localized: "Overnight respiratory rate. An elevated rate relative to your baseline can flag illness or residual strain.")
            )
        )

        let present = components.filter { $0.score != nil }
        let usedLimitedData = present.count < components.count
        guard !present.isEmpty else {
            return RecoveryResult(
                score: nil,
                components: components.map { item in
                    var copy = item
                    copy.weight = 0
                    return copy
                },
                explanation: String(localized: "Not enough overnight data to compute Recovery yet."),
                usedLimitedData: true
            )
        }

        let weightSum = present.reduce(0) { $0 + $1.weight }
        let renormalized: [RecoveryComponent] = components.map { item in
            var copy = item
            if item.score == nil {
                copy.weight = 0
            } else if weightSum > 0 {
                copy.weight = item.weight / weightSum
            }
            return copy
        }

        let score = renormalized.reduce(0) { $0 + $1.contribution }
        return RecoveryResult(
            score: clamp(score, 0, 100),
            components: renormalized,
            explanation: recoveryExplanation(score: score, components: renormalized),
            usedLimitedData: usedLimitedData
        )
    }

    // MARK: - Sleep (0–100)

    /// Sleep = duration vs. target window + 7-day consistency + stage quality.
    ///
    /// Weights when staging is present: duration 50% / consistency 25% / stages 25%.
    /// Without staging the first two are renormalized (67% / 33%).
    static func sleep(
        night: SleepNight?,
        recentNights: [SleepNight],
        targetMinHours: Double,
        targetMaxHours: Double
    ) -> SleepResult {
        guard let night else {
            return SleepResult(
                score: nil,
                night: nil,
                components: [],
                explanation: String(localized: "No sleep recorded for last night.")
            )
        }

        let durationScore = durationComponent(hours: night.asleepHours, min: targetMinHours, max: targetMaxHours)
        let consistency = consistencyComponent(nights: recentNights + [night])
        let stages = night.hasStaging ? stageComponent(night: night) : nil

        var parts: [SleepComponent] = [
            SleepComponent(
                name: String(localized: "Duration"),
                weight: stages == nil ? (2.0 / 3.0) : 0.50,
                score: durationScore.score,
                detail: durationScore.detail
            ),
            SleepComponent(
                name: String(localized: "Consistency"),
                weight: stages == nil ? (1.0 / 3.0) : 0.25,
                score: consistency.score,
                detail: consistency.detail
            )
        ]
        if let stages {
            parts.append(
                SleepComponent(
                    name: String(localized: "Stages"),
                    weight: 0.25,
                    score: stages.score,
                    detail: stages.detail
                )
            )
        }

        let score = parts.reduce(0) { $0 + $1.score * $1.weight }
        let explanation: String
        if durationScore.score < 60 {
            explanation = String(localized: "Sleep is short of your \(targetMinHours.formatted(.number.precision(.fractionLength(1))))–\(targetMaxHours.formatted(.number.precision(.fractionLength(1))))h window.")
        } else if consistency.score < 60 {
            explanation = String(localized: "Hours look fine, but bed/wake times have been drifting.")
        } else if let stages, stages.score < 60 {
            explanation = String(localized: "Duration is on target; stage mix is off your usual deep/REM share.")
        } else {
            explanation = String(localized: "Sleep landed in your target window.")
        }

        return SleepResult(score: clamp(score, 0, 100), night: night, components: parts, explanation: explanation)
    }

    // MARK: - Strain (0–21)

    /// Daily strain from heart-rate-zone minutes plus active energy, scaled 0–21.
    ///
    /// Cardiovascular load:
    ///
    ///     load = 1·z1 + 2·z2 + 3·z3 + 5·z4 + 8·z5  +  kcal / 50
    ///
    /// Zone minutes are estimated from the day's heart-rate samples using
    /// Tanaka max HR (208 − 0.7 × age). Zone weights are exponential so time
    /// in z4/z5 dominates — the same qualitative shape as WHOOP strain.
    ///
    /// Scaling onto 0–21 uses a saturating exponential against the user's
    /// rolling personal-max load (default floor 80 so the first easy day does
    /// not print "21"):
    ///
    ///     strain = 21 × (1 − exp(−load / τ))   where τ = personalMax / 3
    ///
    /// A day equal to the rolling max therefore lands near 20, not 21 — 21 is
    /// reserved for exceeding that max.
    static func strain(
        zoneMinutes: HeartRateZoneMinutes,
        activeEnergyKilocalories: Double,
        personalMaxLoad: Double
    ) -> StrainResult {
        let load =
            zoneMinutes.zone1 * 1 +
            zoneMinutes.zone2 * 2 +
            zoneMinutes.zone3 * 3 +
            zoneMinutes.zone4 * 5 +
            zoneMinutes.zone5 * 8 +
            activeEnergyKilocalories / 50

        let floorMax = max(personalMaxLoad, 80)
        let tau = floorMax / 3
        let score = 21 * (1 - exp(-load / tau))

        let explanation: String
        switch score {
        case 14...:
            explanation = String(localized: "High strain — a lot of time at elevated heart rate.")
        case 8..<14:
            explanation = String(localized: "Moderate strain so far.")
        case 0.1..<8:
            explanation = String(localized: "Light strain — plenty of room left.")
        default:
            explanation = String(localized: "No cardiovascular load recorded yet today.")
        }

        return StrainResult(
            score: clamp(score, 0, 21),
            load: load,
            personalMaxLoad: floorMax,
            zoneMinutes: zoneMinutes,
            activeEnergyKilocalories: activeEnergyKilocalories,
            explanation: explanation
        )
    }

    /// Assign each HR sample to a zone relative to estimated max HR.
    /// Zone bounds (% of max): z1 50–60, z2 60–70, z3 70–80, z4 80–90, z5 90+.
    static func zoneMinutes(
        heartRatesBPM: [(date: Date, bpm: Double)],
        maxHeartRate: Double
    ) -> HeartRateZoneMinutes {
        guard heartRatesBPM.count >= 2, maxHeartRate > 0 else {
            return HeartRateZoneMinutes(zone1: 0, zone2: 0, zone3: 0, zone4: 0, zone5: 0)
        }

        let sorted = heartRatesBPM.sorted { $0.date < $1.date }
        var zones = [Double](repeating: 0, count: 5)

        for index in 1..<sorted.count {
            let interval = sorted[index].date.timeIntervalSince(sorted[index - 1].date)
            // Ignore gaps over 5 minutes (watch came off, workout ended).
            guard interval > 0, interval <= 300 else { continue }
            let minutes = interval / 60
            let fraction = sorted[index].bpm / maxHeartRate
            let zoneIndex: Int
            switch fraction {
            case ..<0.50: continue
            case ..<0.60: zoneIndex = 0
            case ..<0.70: zoneIndex = 1
            case ..<0.80: zoneIndex = 2
            case ..<0.90: zoneIndex = 3
            default: zoneIndex = 4
            }
            zones[zoneIndex] += minutes
        }

        return HeartRateZoneMinutes(
            zone1: zones[0],
            zone2: zones[1],
            zone3: zones[2],
            zone4: zones[3],
            zone5: zones[4]
        )
    }

    // MARK: - Weight trend

    /// 7-day rolling mean of daily body mass. Raw daily values are too noisy
    /// to drive a dashboard status; the rolling mean is the primary signal.
    static func rollingAverage(values: [(date: Date, kg: Double)], windowDays: Int = 7) -> [(date: Date, kg: Double)] {
        let sorted = values.sorted { $0.date < $1.date }
        return sorted.map { point in
            let windowStart = point.date.adding(days: -(windowDays - 1))
            let window = sorted.filter { $0.date >= windowStart && $0.date <= point.date }
            let mean = window.reduce(0) { $0 + $1.kg } / Double(window.count)
            return (point.date, mean)
        }
    }

    /// Slope of the 7-day average, kg / week, via simple least-squares on the
    /// last `lookbackDays` rolling-average points.
    static func weeklySlopeKg(rolling: [(date: Date, kg: Double)], lookbackDays: Int = 14) -> Double? {
        let slice = rolling.suffix(lookbackDays)
        guard slice.count >= 4 else { return nil }
        let xs = slice.map { $0.date.timeIntervalSince1970 / 86_400 }
        let ys = slice.map(\.kg)
        let n = Double(xs.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumXX = xs.reduce(0) { $0 + $1 * $1 }
        let denom = n * sumXX - sumX * sumX
        guard abs(denom) > 0.0001 else { return nil }
        let slopePerDay = (n * sumXY - sumX * sumY) / denom
        return slopePerDay * 7
    }

    /// Decision rule against the user's editable target rate of change (kg/week).
    ///
    /// - On track: slope within ±0.15 kg/week of the target (or within 40% of
    ///   the target magnitude, whichever is larger).
    /// - Flat: |slope| < 0.10 kg/week while the target is meaningfully non-zero.
    /// - Losing/gaining fast: same sign as the target but ≥ 1.75× as steep, or
    ///   the opposite sign from the intended direction.
    static func weightStatus(slopeKgPerWeek: Double?, targetKgPerWeek: Double) -> WeightTrendStatus {
        guard let slope = slopeKgPerWeek else { return .unknown }
        let tolerance = max(0.15, abs(targetKgPerWeek) * 0.4)
        if abs(slope - targetKgPerWeek) <= tolerance {
            return .onTrack
        }
        if abs(targetKgPerWeek) >= 0.15, abs(slope) < 0.10 {
            return .flat
        }
        if targetKgPerWeek < 0 {
            return slope < targetKgPerWeek * 1.75 ? .losingFast : (slope > 0 ? .gainingFast : .onTrack)
        }
        if targetKgPerWeek > 0 {
            return slope > targetKgPerWeek * 1.75 ? .gainingFast : (slope < 0 ? .losingFast : .onTrack)
        }
        return abs(slope) < 0.10 ? .flat : (slope < 0 ? .losingFast : .gainingFast)
    }

    // MARK: - Correlations (trends)

    /// Pearson r between two aligned series. Returns nil if variance is zero
    /// or there are fewer than 5 pairs.
    static func pearson(_ xs: [Double], _ ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count >= 5 else { return nil }
        let n = Double(xs.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var num = 0.0
        var denX = 0.0
        var denY = 0.0
        for index in xs.indices {
            let dx = xs[index] - meanX
            let dy = ys[index] - meanY
            num += dx * dy
            denX += dx * dx
            denY += dy * dy
        }
        let den = sqrt(denX * denY)
        guard den > 0 else { return nil }
        return num / den
    }

    // MARK: - Internals

    private static func makeComponent(
        name: String,
        symbol: String,
        defaultWeight: Double,
        value: Double?,
        baseline: BaselineStats?,
        invert: Bool,
        unit: String,
        higherIsBetterNote: String
    ) -> RecoveryComponent {
        guard let value else {
            return RecoveryComponent(
                name: name,
                symbolName: symbol,
                weight: defaultWeight,
                score: nil,
                zScore: nil,
                rawValue: nil,
                baselineMean: baseline?.mean,
                unitLabel: unit,
                note: String(localized: "No sample last night.")
            )
        }
        let sd = max(baseline?.standardDeviation ?? 1, 0.01)
        let mean = baseline?.mean ?? value
        let rawZ = (value - mean) / sd
        let z = invert ? -rawZ : rawZ
        return RecoveryComponent(
            name: name,
            symbolName: symbol,
            weight: defaultWeight,
            score: componentScore(z: z),
            zScore: z,
            rawValue: value,
            baselineMean: baseline?.mean,
            unitLabel: unit,
            note: higherIsBetterNote
        )
    }

    private static func recoveryExplanation(score: Double, components: [RecoveryComponent]) -> String {
        let drivers = components.compactMap { component -> (RecoveryComponent, Double)? in
            guard let z = component.zScore else { return nil }
            return (component, z)
        }
        let negatives = drivers.filter { $0.1 < -0.4 }.sorted { $0.1 < $1.1 }
        let positives = drivers.filter { $0.1 > 0.4 }.sorted { $0.1 > $1.1 }

        func names(_ items: [(RecoveryComponent, Double)]) -> String {
            items.prefix(2).map(\.0.name).joined(separator: ", ")
        }

        switch score {
        case 67...:
            if let top = positives.first {
                return String(localized: "Recovery is solid — \(top.0.name) is better than usual.")
            }
            return String(localized: "Recovery is in a good place relative to your baseline.")
        case 34..<67:
            if let down = negatives.first, let up = positives.first {
                return String(localized: "Recovery is mixed — \(down.0.name) down, \(up.0.name) up.")
            }
            if let down = negatives.first {
                return String(localized: "Recovery is middling — \(down.0.name) is off baseline.")
            }
            return String(localized: "Recovery is around your typical range.")
        default:
            if negatives.isEmpty {
                return String(localized: "Recovery is lower than usual.")
            }
            return String(localized: "Recovery is lower than usual — \(names(negatives)).")
        }
    }

    private static func durationComponent(hours: Double, min: Double, max: Double) -> (score: Double, detail: String) {
        let score: Double
        if hours >= min && hours <= max {
            score = 100
        } else if hours < min {
            score = clamp(100 * (hours / max(min, 0.1)), 0, 100)
        } else {
            // Mild oversleep penalty — 50% extra duration → score 60.
            let overshoot = (hours - max) / max(max, 0.1)
            score = clamp(100 * (1 - 0.4 * overshoot), 0, 100)
        }
        let range = "\(min.formatted(.number.precision(.fractionLength(1))))–\(max.formatted(.number.precision(.fractionLength(1))))h"
        let actual = hours.formatted(.number.precision(.fractionLength(1)))
        return (score, String(localized: "\(actual)h asleep vs. \(range) target."))
    }

    private static func consistencyComponent(nights: [SleepNight]) -> (score: Double, detail: String) {
        let unique = Dictionary(nights.map { (CalendarDay.start(of: $0.morning), $0) }, uniquingKeysWith: { _, last in last })
        let lastSeven = unique.values.sorted { $0.morning < $1.morning }.suffix(7)
        guard lastSeven.count >= 3 else {
            return (70, String(localized: "Need a few more nights to judge consistency."))
        }

        let bedMinutes = lastSeven.map { minutesFromMidnight($0.bedtime) }
        let wakeMinutes = lastSeven.map { minutesFromMidnight($0.wakeTime) }
        let bedSD = standardDeviation(bedMinutes)
        let wakeSD = standardDeviation(wakeMinutes)
        let combined = hypot(bedSD, wakeSD)

        // 20 min combined SD → 100; 90 min → 0.
        let score = clamp(100 * (90 - combined) / 70, 0, 100)
        let formatted = combined.formatted(.number.precision(.fractionLength(0)))
        return (score, String(localized: "Bed/wake spread ≈ \(formatted) min over the last \(lastSeven.count) nights."))
    }

    private static func stageComponent(night: SleepNight) -> (score: Double, detail: String) {
        let asleep = max(night.totalAsleep, 1)
        let deepPct = night.duration(of: .deep) / asleep
        let remPct = night.duration(of: .rem) / asleep
        let awakePct = night.duration(of: .awake) / asleep

        // Adult deep typically ~13–23% of TST; REM ~18–28%. These are used as
        // *targets for the user's night*, not a comparison against other people —
        // HealthKit rarely has a long enough staging history for a personal
        // baseline, so we score against physiological ranges.
        let deepScore = gaussianPercent(deepPct, center: 0.18, width: 0.07)
        let remScore = gaussianPercent(remPct, center: 0.22, width: 0.08)
        let awakeScore = clamp(100 * (0.25 - awakePct) / 0.17, 0, 100)

        let score = 0.4 * deepScore + 0.4 * remScore + 0.2 * awakeScore
        let deep = (deepPct * 100).formatted(.number.precision(.fractionLength(0)))
        let rem = (remPct * 100).formatted(.number.precision(.fractionLength(0)))
        return (score, String(localized: "Deep \(deep)% · REM \(rem)% of time asleep."))
    }

    private static func gaussianPercent(_ value: Double, center: Double, width: Double) -> Double {
        let z = (value - center) / width
        return clamp(100 * exp(-0.5 * z * z), 0, 100)
    }

    private static func minutesFromMidnight(_ date: Date) -> Double {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
    }

    /// Wrap-aware SD helper: bedtime 23:50 and 00:10 should be close, not 23h apart.
    /// Circular treatment is approximated by scoring each time as minutes from
    /// the series median, then taking the linear SD — good enough for 7 points.
    private static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        let circular = values.map { value -> Double in
            // Map into a −12h…+12h window around the median.
            let median = values.sorted()[values.count / 2]
            var delta = value - median
            if delta > 720 { delta -= 1440 }
            if delta < -720 { delta += 1440 }
            return median + delta
        }
        let mean = circular.reduce(0, +) / Double(circular.count)
        let variance = circular.reduce(0) { $0 + pow($1 - mean, 2) } / Double(circular.count - 1)
        return sqrt(variance)
    }

    static func clamp(_ value: Double, _ minValue: Double, _ maxValue: Double) -> Double {
        min(max(value, minValue), maxValue)
    }
}
