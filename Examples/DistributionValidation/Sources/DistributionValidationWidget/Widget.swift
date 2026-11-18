import SwiftUI
import WidgetKit

@main
struct DistributionValidationWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DistributionValidation", provider: Provider()) { _ in
            Text("Distribution validation")
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Distribution validation")
        .description("A static widget for testing distribution packaging.")
        .supportedFamilies([.systemSmall])
    }

    struct Entry: TimelineEntry {
        let date: Date
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry {
            Entry(date: Date())
        }

        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            completion(placeholder(in: context))
        }

        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Timeline(entries: [placeholder(in: context)], policy: .never))
        }
    }
}
