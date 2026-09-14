import Foundation
@testable import Biceptional
import Testing

struct ScoringEngineTests {
    @Test func componentScoreMidpoint() {
        #expect(ScoringEngine.componentScore(z: 0) == 50)
        #expect(ScoringEngine.componentScore(z: 2) == 80)
        #expect(ScoringEngine.componentScore(z: -2) == 20)
        #expect(ScoringEngine.componentScore(z: 10) == 100)
        #expect(ScoringEngine.componentScore(z: -10) == 0)
    }

    @Test func recoveryRenormalizesMissingRespiratoryRate() {
        let physiology = OvernightPhysiology(hrvSDNN: 50, restingHeartRate: 55, respiratoryRate: nil, oxygenSaturation: nil)
        let hrv = BaselineStats(mean: 50, standardDeviation: 10, sampleCount: 30)
        let rhr = BaselineStats(mean: 55, standardDeviation: 4, sampleCount: 30)
        let result = ScoringEngine.recovery(
            physiology: physiology,
            hrvBaseline: hrv,
            rhrBaseline: rhr,
            rrBaseline: nil,
            sleepScore: 80
        )
        #expect(result.score != nil)
        let rr = result.components.first { $0.name.contains("Respiratory") }
        #expect(rr?.weight == 0)
        let weightSum = result.components.reduce(0) { $0 + $1.weight }
        #expect(abs(weightSum - 1) < 0.001)
    }

    @Test func sleepDurationInWindowIsPerfect() {
        let night = SleepNight(
            morning: Date(),
            bedtime: Date().addingTimeInterval(-8 * 3600),
            wakeTime: Date(),
            totalAsleep: 8 * 3600,
            timeInBed: 8.2 * 3600,
            stages: [],
            hasStaging: false
        )
        let result = ScoringEngine.sleep(night: night, recentNights: [], targetMinHours: 7.5, targetMaxHours: 8.5)
        let duration = result.components.first { $0.name == "Duration" }
        #expect(duration?.score == 100)
    }

    @Test func strainIsBounded() {
        let zones = HeartRateZoneMinutes(zone1: 40, zone2: 30, zone3: 20, zone4: 10, zone5: 5)
        let result = ScoringEngine.strain(zoneMinutes: zones, activeEnergyKilocalories: 800, personalMaxLoad: 80)
        #expect(result.score >= 0)
        #expect(result.score <= 21)
    }

    @Test func weightStatusOnTrack() {
        let status = ScoringEngine.weightStatus(slopeKgPerWeek: -0.38, targetKgPerWeek: -0.4)
        #expect(status == .onTrack)
    }

    @Test func weightStatusLosingFast() {
        let status = ScoringEngine.weightStatus(slopeKgPerWeek: -1.0, targetKgPerWeek: -0.4)
        #expect(status == .losingFast)
    }

    @Test func pearsonPerfectCorrelation() {
        let r = ScoringEngine.pearson([1, 2, 3, 4, 5], [2, 4, 6, 8, 10])
        #expect(r != nil)
        #expect(abs((r ?? 0) - 1) < 0.0001)
    }
}
