import WidgetKit
import SwiftUI
import MacroMarkKit

struct InstantCaptureEntry: TimelineEntry {
    let date: Date
}

struct InstantCaptureWidgetView: View {
    var entry: InstantCaptureEntry

    var body: some View {
        Image(systemName: "mic.fill")
            .font(.title)
            .widgetURL(AppRoute.instantCaptureURL)
    }
}

struct SystemCaptureWidgetView: View {
    var entry: InstantCaptureEntry

    var body: some View {
        Image(systemName: "keyboard")
            .font(.title)
            .widgetURL(AppRoute.systemCaptureURL)
    }
}

struct InstantCaptureWidget: Widget {
    let kind: String = "InstantCaptureWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StaticProvider()) { entry in
            InstantCaptureWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Instant Capture")
        .description("Tap to start dictating instantly without timeouts.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct SystemCaptureWidget: Widget {
    let kind: String = "SystemCaptureWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StaticProvider()) { entry in
            SystemCaptureWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("System Capture")
        .description("Tap to capture using the standard system keyboard/dictation UI.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct StaticProvider: TimelineProvider {
    func placeholder(in context: Context) -> InstantCaptureEntry {
        InstantCaptureEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (InstantCaptureEntry) -> ()) {
        completion(InstantCaptureEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let timeline = Timeline(entries: [InstantCaptureEntry(date: Date())], policy: .never)
        completion(timeline)
    }
}
