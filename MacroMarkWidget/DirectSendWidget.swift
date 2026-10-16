import WidgetKit
import SwiftUI
import MacroMarkKit

private struct DirectSendEntry: TimelineEntry {
    let date: Date
    let pendingCount: Int
}

private struct DirectSendProvider: TimelineProvider {
    func placeholder(in context: Context) -> DirectSendEntry { DirectSendEntry(date: Date(), pendingCount: 2) }

    func getSnapshot(in context: Context, completion: @escaping (DirectSendEntry) -> Void) { completion(entry()) }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DirectSendEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    private func entry() -> DirectSendEntry {
        DirectSendEntry(date: Date(), pendingCount: max(0, UserDefaults(suiteName: DirectSendSharedState.appGroup)?
            .integer(forKey: DirectSendSharedState.pendingCountKey) ?? 0))
    }
}

struct DirectSendWidget: Widget {
    let kind = "DirectSendWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DirectSendProvider()) { entry in
            VStack(spacing: 2) {
                Image(systemName: "text.bubble")
                Text("\(entry.pendingCount) pending").font(.caption2)
            }
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(AppRoute.directSendRepliesURL)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("MacroMark replies, \(entry.pendingCount) pending notes")
            .accessibilityHint("Opens replies in MacroMark.")
        }
        .configurationDisplayName("Replies and deliveries")
        .description("Open replies and see how many notes are waiting for delivery.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }
}
