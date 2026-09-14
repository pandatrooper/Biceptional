import SwiftUI
import WidgetKit

struct BiceptionalWidgetsEntry: TimelineEntry {
    let date: Date
    let snapshot: TodaySnapshotPayload
}

struct BiceptionalProvider: TimelineProvider {
    func placeholder(in context: Context) -> BiceptionalWidgetsEntry {
        BiceptionalWidgetsEntry(
            date: .now,
            snapshot: TodaySnapshotPayload(
                date: .now,
                recoveryScore: 72,
                recoveryExplanation: "Recovery is solid — HRV is better than usual.",
                sleepScore: 81,
                sleepHours: 7.8,
                strainScore: 6.2,
                steps: 4320,
                activeCalories: 210
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (BiceptionalWidgetsEntry) -> Void) {
        completion(BiceptionalWidgetsEntry(date: .now, snapshot: TodaySnapshotPayload.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BiceptionalWidgetsEntry>) -> Void) {
        let entry = BiceptionalWidgetsEntry(date: .now, snapshot: TodaySnapshotPayload.load())
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct RecoveryWidgetView: View {
    var entry: BiceptionalWidgetsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "heart.fill")
                Text(String(localized: "Recovery"))
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(.secondary)

            Text(scoreText(entry.snapshot.recoveryScore))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(bandColor(entry.snapshot.recoveryScore))

            if family != .accessoryCircular && family != .accessoryInline {
                Text(entry.snapshot.recoveryExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let sleep = entry.snapshot.sleepScore {
                    Label(
                        String(localized: "Sleep \(sleep.formatted(.number.precision(.fractionLength(0))))"),
                        systemImage: "moon.zzz.fill"
                    )
                    .font(.caption)
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Today’s Recovery \(scoreText(entry.snapshot.recoveryScore)), sleep \(scoreText(entry.snapshot.sleepScore))"))
    }

    private func scoreText(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—"
    }

    private func bandColor(_ score: Double?) -> Color {
        guard let score else { return .secondary }
        switch score {
        case 67...: return .green
        case 34..<67: return .orange
        default: return .red
        }
    }
}

@main
struct BiceptionalWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RecoveryWidget()
        RecoveryLockScreenWidget()
    }
}

struct RecoveryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BiceptionalRecovery", provider: BiceptionalProvider()) { entry in
            RecoveryWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Recovery"))
        .description(String(localized: "Today’s Recovery ring and Sleep score."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct RecoveryLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BiceptionalRecoveryLock", provider: BiceptionalProvider()) { entry in
            RecoveryWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Recovery"))
        .description(String(localized: "Lock Screen Recovery score."))
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}
