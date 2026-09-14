import SwiftUI

struct ScoreRing: View {
    var score: Double?
    var maxScore: Double = 100
    var lineWidth: CGFloat = 14
    var color: Color

    private var progress: Double {
        guard let score, maxScore > 0 else { return 0 }
        return ScoringEngine.clamp(score / maxScore, 0, 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: progress)
            VStack(spacing: 2) {
                Text(scoreText)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(color)
                Text(maxScore == 21 ? String(localized: "Strain") : String(localized: "out of \(Int(maxScore))"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(maxScore == 21 ? String(localized: "Strain") : String(localized: "Score"))
        .accessibilityValue(score.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? String(localized: "Unavailable"))
    }

    private var scoreText: String {
        guard let score else { return "—" }
        return score.formatted(.number.precision(.fractionLength(score < 10 ? 1 : 0)))
    }
}

struct MetricCard<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
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
