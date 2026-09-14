import SwiftUI

struct BiceptionalCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 1)
            )
    }
}

struct HeroRing: View {
    var score: Double?
    var maxScore: Double = 100
    @ScaledMetric(relativeTo: .largeTitle) private var lineWidth: CGFloat = 16

    private var band: RecoveryBand { RecoveryBand(score: score) }

    private var progress: Double {
        guard let score, maxScore > 0 else { return 0 }
        return ScoringEngine.clamp(score / maxScore, 0, 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(band.color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [band.color.opacity(0.55), band.color],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: band.color.opacity(score == nil ? 0 : 0.45), radius: 12, y: 0)
                .animation(.easeInOut(duration: 0.7), value: progress)

            VStack(spacing: 6) {
                Text(band.chipTitle)
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(band.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(band.color.opacity(0.14), in: Capsule())
                Text(scoreText)
                    .font(Theme.score)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(String(localized: "Recovery"))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Recovery"))
        .accessibilityValue(accessibilityValue)
    }

    private var scoreText: String {
        guard let score else { return "—" }
        return score.formatted(.number.precision(.fractionLength(0)))
    }

    private var accessibilityValue: String {
        guard let score else { return String(localized: "Unavailable") }
        return "\(band.localizedName), \(score.formatted(.number.precision(.fractionLength(0))))"
    }
}

struct StrainArc: View {
    var score: Double?
    @ScaledMetric(relativeTo: .title) private var lineWidth: CGFloat = 10

    private var intensity: StrainIntensity { StrainIntensity(score: score) }
    private var progress: Double {
        ScoringEngine.clamp((score ?? 0) / 21, 0, 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.12, to: 0.88)
                .stroke(Color.hairline, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(90))
            Circle()
                .trim(from: 0.12, to: 0.12 + 0.76 * progress)
                .stroke(
                    intensity.color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .animation(.easeInOut(duration: 0.6), value: progress)

            VStack(spacing: 2) {
                Text(scoreText)
                    .font(Theme.display(28))
                    .monospacedDigit()
                Text(String(localized: "/ 21"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .offset(y: 4)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Strain"))
        .accessibilityValue(
            "\(scoreText) \(String(localized: "out of 21")), \(intensity.localizedName)"
        )
    }

    private var scoreText: String {
        (score ?? 0).formatted(.number.precision(.fractionLength(1)))
    }
}

struct WeekStrip: View {
    var snapshots: [DailySnapshot]
    var selected: Date = CalendarDay.start(of: .now)

    var body: some View {
        HStack(spacing: 10) {
            ForEach(days, id: \.self) { day in
                let score = snapshots.first { CalendarDay.start(of: $0.day) == day }?.recoveryScore
                VStack(spacing: 6) {
                    Circle()
                        .fill(score == nil ? Color.hairline : Color.recoveryBand(score))
                        .frame(width: 10, height: 10)
                    Text(Formatters.weekday.string(from: day))
                        .font(.caption2.weight(CalendarDay.start(of: day) == selected ? .bold : .regular))
                        .foregroundStyle(CalendarDay.start(of: day) == selected ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Formatters.weekday.string(from: day))
                .accessibilityValue(
                    score.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? String(localized: "No score")
                )
            }
        }
    }

    private var days: [Date] {
        let today = CalendarDay.start(of: .now)
        return (0..<7).reversed().map { today.adding(days: -$0) }
    }
}

struct UpdatedCaption: View {
    var date: Date?

    var body: some View {
        if let date {
            Text(String(localized: "As of \(Formatters.shortTime.string(from: date))"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct SleepStageBar: View {
    var night: SleepNight
    var height: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            let total = max(night.timeInBed, 1)
            HStack(spacing: 1) {
                ForEach(night.stages) { interval in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.stage(interval.stage))
                        .frame(width: max(1, proxy.size.width * interval.duration / total))
                        .accessibilityLabel(interval.stage.localizedName)
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Sleep stages"))
    }
}

struct EmptyStateView: View {
    var systemImage: String
    var title: String
    var message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
    }
}
